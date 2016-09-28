
import Foundation
import XMPPFramework
import ReactiveCocoa
import ReachabilitySwift
import p2_OAuth2
import enum Result.NoError

class XFDelegateModuleProxy: NSObject {
    private let _xmppQueue = dispatch_queue_create("xmppq-\(NSUUID().UUIDString)", nil);
    init(module: XMPPModule) {
        super.init();
        module.addDelegate(self, delegateQueue: self._xmppQueue);
    }
    deinit { } // TODO: do i have to release the dispatch queue?
}

class XFStreamDelegateProxy: NSObject, XMPPStreamDelegate {
    // because of XMPPFramework's haphazard design, there isn't a protocol
    // that consistently represents addDelegate. so we have to do this all over again.
    private let _xmppQueue = dispatch_queue_create("xmppq-stream", nil);
    init(stream: XMPPStream) {
        super.init();
        stream.addDelegate(self, delegateQueue: self._xmppQueue);
    }

    private let _connectProxy = ManagedSignal<Bool>();
    var connectSignal: Signal<Bool, NoError> { get { return self._connectProxy.signal; } }
    @objc internal func xmppStreamDidConnect(sender: XMPPStream!) {
        self._connectProxy.observer.sendNext(true);
    }

    private let _authenticatedProxy = ManagedSignal<Bool>();
    var authenticatedSignal: Signal<Bool, NoError> { get { return self._authenticatedProxy.signal; } }
    @objc internal func xmppStreamDidAuthenticate(sender: XMPPStream!) {
        self._authenticatedProxy.observer.sendNext(true);
    }

    // on disconnect, we are both unconnected and unauthenticated.
    @objc internal func xmppStreamDidDisconnect(sender: XMPPStream!, withError error: NSError!) {
        self._connectProxy.observer.sendNext(false);
        self._authenticatedProxy.observer.sendNext(false);
    }

    private let _messageProxy = ManagedSignal<XMPPMessage>();
    var messageSignal: Signal<XMPPMessage, NoError> { get { return self._messageProxy.signal; } };
    @objc internal func xmppStream(sender: XMPPStream!, didReceiveMessage message: XMPPMessage!) {
        if message.isChatMessageWithBody() || ChatState.fromMessage(message) != nil {
            self._messageProxy.observer.sendNext(message);
        }
    }
}

class XFRosterDelegateProxy: XFDelegateModuleProxy, XMPPRosterDelegate {
    private let _usersProxy = ManagedSignal<[XMPPUser]>();
    var usersSignal: Signal<[XMPPUser], NoError> { get { return self._usersProxy.signal; } }
    @objc internal func xmppRosterDidPopulate(sender: XMPPRosterMemoryStorage!) {
        self._usersProxy.observer.sendNext(sender.sortedUsersByName() as! [XMPPUser]!);
    }
    @objc internal func xmppRosterDidChange(sender: XMPPRosterMemoryStorage!) {
        self._usersProxy.observer.sendNext(sender.sortedUsersByName() as! [XMPPUser]!);
    }

    /*@objc internal func didUpdateResource(resource: XMPPResourceMemoryStorageObject!, withUser: XMPPResourceMemoryStorageObject!) {
        NSLog("resource updated");
    }*/
}

class Connection {
    internal let stream: XMPPStream;
    internal let rosterStorage: XMPPRosterMemoryStorage;
    internal let roster: XMPPRoster;
    internal let reconnect: XMPPReconnect;
    internal let reachability: Reachability?;

    private var _connectionAttempt = 0;

    private let _streamDelegateProxy: XFStreamDelegateProxy;
    private let _rosterDelegateProxy: XFRosterDelegateProxy;

    init() {
        // xmpp logging
        DDLog.addLogger(DDTTYLogger.sharedInstance(), withLevel: DDLogLevel.All);

        // set up network availability detection
        self.reachability = try? Reachability.reachabilityForInternetConnection();

        // setup
        self.rosterStorage = XMPPRosterMemoryStorage();
        self.roster = XMPPRoster.init(rosterStorage: self.rosterStorage);
        self.reconnect = XMPPReconnect();

        self.stream = XMPPStream();
        self.stream.hostName = "talk.google.com";

        // init proxies
        self._streamDelegateProxy = XFStreamDelegateProxy(stream: self.stream);
        self._rosterDelegateProxy = XFRosterDelegateProxy(module: self.roster);

        // set up reactions and plugins
        self.prepare();
        self.roster.activate(self.stream);
        self.reconnect.activate(self.stream);
    }

    func connect(account: String) {
        if stream.isConnected() { stream.disconnect(); }

        self.stream.myJID = XMPPJID.jidWithString(account);
        try! stream.connectWithTimeout(NSTimeInterval(10));
    }

    // plumb through proxies
    var connected: Signal<Bool, NoError> { get { return self._streamDelegateProxy.connectSignal; } };
    var authenticated: Signal<Bool, NoError> { get { return self._streamDelegateProxy.authenticatedSignal; } };
    var users: Signal<[XMPPUser], NoError> { get { return self._rosterDelegateProxy.usersSignal.debounce(NSTimeInterval(0.15), onScheduler: QueueScheduler.mainQueueScheduler); } };

    // own user
    private var _myself = MutableProperty<Contact?>(nil);
    var myself: Signal<Contact?, NoError> { get { return self._myself.signal; } };
    var myself_: Contact? { get { return self._myself.value; } };

    // latest message
    private let _latestMessageSignal = ManagedSignal<Message>();
    var latestMessage: Signal<Message, NoError> { get { return self._latestMessageSignal.signal; } };

    // latest activity
    private let _latestActivitySignal = ManagedSignal<Contact>();
    var latestActivity: Signal<Contact, NoError> { get { return self._latestActivitySignal.signal; } };

    // managed contacts (impl in prepare())
    private let _contactsCache = QuickCache<String, Contact>();
    private var _contactsSignal: Signal<[Contact], NoError>?;
    var contacts: Signal<[Contact], NoError> { get { return self._contactsSignal!; } };

    // are we connected to the internet?
    private let _hasInternet = MutableProperty<Bool>(true); // assume true in case we have nothing.
    var hasInternet: Signal<Bool, NoError> { get { return self._hasInternet.signal; } };
    var hasInternet_: Bool { get { return self._hasInternet.value; } };

    // sets up our own reactions to basic xmpp things
    private func prepare() {
        // if we are authenticated, send initial status and set some stuff up
        self.authenticated.skipRepeats().observeNext { authenticated in
            if authenticated == true {
                self.stream.sendElement(XMPPPresence(name: "presence")); // TODO: this init is silly. this is just the NSXML init.
                self._myself.modify({ _ in Contact(xmppUser: XMPPUserMemoryStorageObject.init(JID: self.stream.myJID), connection: self) });
            }
        }

        // create managed contacts
        self._contactsSignal = self.users.map { users in
            users.map { user in
                self._contactsCache.get(user.jid().bare(), update: { contact in contact.update(user); }, orElse: { Contact(xmppUser: user, connection: self); });
            };
        }

        // add new messages to the appropriate conversations.
        self._streamDelegateProxy.messageSignal.observeNext { rawMessage in
            if let with = self._contactsCache.get(rawMessage.from().bare()) {
                let conversation = with.conversation;

                if rawMessage.isMessageWithBody() {
                    self._latestActivitySignal.observer.sendNext(with);
                    let message = Message(from: with, body: rawMessage.body(), at: NSDate(), conversation: conversation);
                    conversation.addMessage(message);
                    self._latestMessageSignal.observer.sendNext(message);
                } else if let state = ChatState.fromMessage(rawMessage) {
                    self._latestActivitySignal.observer.sendNext(with);
                    conversation.setChatState(state);
                }
            } else {
                NSLog("unrecognized user \(rawMessage.from().bare())!");
            }
        }

        // if we have a reachability instance, wire up that signal.
        if let reach = self.reachability {
            reach.whenReachable = { _ in self._hasInternet.modify { _ in true; } };
            reach.whenUnreachable = { _ in self._hasInternet.modify { _ in false; } };
            do { try reach.startNotifier(); } catch _ { NSLog("could not start reachability"); }
        }
    }

    // send an outbound message in a way that handles the plumbing correctly.
    func sendMessage(to: Contact, _ text: String) {
        let xmlBody = NSXMLElement(name: "body");
        xmlBody.setStringValue(text, resolvingEntities: false);

        let xmlMessage = NSXMLElement(name: "message");
        xmlMessage.addAttributeWithName("type", stringValue: "chat");
        xmlMessage.addAttributeWithName("to", stringValue: to.inner.jid().full());
        xmlMessage.addChild(xmlBody);

        self.stream.sendElement(xmlMessage);

        let message = Message(from: self.myself_!, body: text, at: NSDate(), conversation: to.conversation);
        self._latestMessageSignal.observer.sendNext(message);
        to.conversation.addMessage(message);
        // TODO: i don't like that this is a separate set of code from the foreign incoming.
    }

    func sendChatState(to: Contact, _ state: ChatState) {
        let xmlMessage = NSXMLElement(name: "message");
        xmlMessage.addAttributeWithName("type", stringValue: "chat");
        xmlMessage.addAttributeWithName("to", stringValue: to.inner.jid().full());
        let xmppMessage = XMPPMessage(fromElement: xmlMessage);
        switch (state) {
        case .Active: xmppMessage.addActiveChatState();
        case .Composing: xmppMessage.addComposingChatState();
        case .Inactive: xmppMessage.addInactiveChatState();
        case .Paused: xmppMessage.addPausedChatState();
        }
        self.stream.sendElement(xmppMessage);
    }
}

class OAuthConnection: Connection {
    private var _oauth2: OAuth2CodeGrant?;

    override private func prepare() {
        // if we are xmpp-connected, authenticate
        self.connected.skipRepeats().observeNext { connected in
            if connected == true {
                // need to make a new instance each attempt or else keychain access gets wonky race conditions.
                self._oauth2 = OAuth2CodeGrant(settings: ST.oauth.settings);
                guard let oauth = self._oauth2 else { return };

                oauth.verbose = true;
                oauth.onAuthorize = { _ in
                    // extract our token.
                    guard let password = oauth.accessToken else { return; }
                    try! self.stream.authenticateWithGoogleAccessToken(password);
                }
                oauth.authConfig.authorizeEmbedded = false;
                oauth.authorize();
            }
        }

        super.prepare();
    }
}

class DemoConnection: Connection {
    static let demoUsers: [DemoUser] = [
        DemoUser(name: "Zoe", index: 1),
        DemoUser(name: "Malcolm", index: 3),
        DemoUser(name: "Jayne", index: 4),
        DemoUser(name: "Wash", index: 5),
        DemoUser(name: "Inara", index: 6),
        DemoUser(name: "River", index: 7),
        DemoUser(name: "Simon", index: 8),
        DemoUser(name: "Britta", index: 9),
        DemoUser(name: "Shepard", index: 10),
        DemoUser(name: "Annie", index: 11),
        DemoUser(name: "Shirley", index: 12),
        DemoUser(name: "Jeff", index: 13),
        DemoUser(name: "Troy", index: 14),
        DemoUser(name: "Pierce", index: 15),
        DemoUser(name: "Abed", index: 16)
    ];

    private var _contacts: MutableProperty<[Contact]>?;

    private var _connected = MutableProperty<Bool>(false);
    override var connected: Signal<Bool, NoError> { get { return self._connected.signal; } };
    private var _authenticated = MutableProperty<Bool>(false);
    override var authenticated: Signal<Bool, NoError> { get { return self._authenticated.signal; } };

    override func connect(account: String) {
        self._connected.modify({ _ in true });
        self._authenticated.modify({ _ in true });
        self._myself.modify({ _ in DemoContact(name: "Kaylee", index: 2, connection: self) });
        self._contacts!.modify({ _ in DemoConnection.demoUsers.map({ user in DemoContact(user: user, connection: self) }) });
    }

    override private func prepare() {
        self._contacts = MutableProperty<[Contact]>([]);
        self._contactsSignal = self._contacts!.signal;

        if let reach = self.reachability {
            reach.whenReachable = { _ in self._hasInternet.modify { _ in true; } };
            reach.whenUnreachable = { _ in self._hasInternet.modify { _ in false; } };
            do { try reach.startNotifier(); } catch _ { NSLog("could not start reachability"); }
        }
    }

    override func sendMessage(to: Contact, _ text: String) {
        let message = Message(from: self.myself_!, body: text, at: NSDate(), conversation: to.conversation);
        self._latestMessageSignal.observer.sendNext(message);
        to.conversation.addMessage(message);
    }

    override func sendChatState(to: Contact, _ state: ChatState) {
        // nothing;
    }
}

