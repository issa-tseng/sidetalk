
import Foundation
import XMPPFramework
import ReactiveCocoa
import ReactiveSwift
import Reachability
import p2_OAuth2
import enum Result.NoError

class XFDelegateModuleProxy: NSObject {
    private let _xmppQueue = DispatchQueue.init(label: "xmppq-\(NSUUID().uuidString)");
    init(module: XMPPModule) {
        super.init();
        module.addDelegate(self, delegateQueue: self._xmppQueue);
    }
    deinit { } // TODO: do i have to release the dispatch queue?
}

class XFStreamDelegateProxy: NSObject, XMPPStreamDelegate {
    // because of XMPPFramework's haphazard design, there isn't a protocol
    // that consistently represents addDelegate. so we have to do this all over again.
    private let _xmppQueue = DispatchQueue.init(label: "xmppq-stream");
    init(stream: XMPPStream) {
        super.init();
        stream.addDelegate(self, delegateQueue: self._xmppQueue);
    }

    private let _connectProxy = ManagedSignal<Bool>();
    var connectSignal: Signal<Bool, NoError> { get { return self._connectProxy.signal; } }
    @objc internal func xmppStreamDidConnect(sender: XMPPStream!) {
        self._connectProxy.observer.send(value: true);
    }

    private let _authenticatedProxy = ManagedSignal<Bool>();
    var authenticatedSignal: Signal<Bool, NoError> { get { return self._authenticatedProxy.signal; } }
    @objc internal func xmppStreamDidAuthenticate(_ sender: XMPPStream!) {
        self._authenticatedProxy.observer.send(value: true);
    }

    // on disconnect, we are both unconnected and unauthenticated.
    @objc internal func xmppStreamDidDisconnect(_ sender: XMPPStream!, withError error: Error!) {
        self._connectProxy.observer.send(value: false);
        self._authenticatedProxy.observer.send(value: false);
    }

    private let _messageProxy = ManagedSignal<XMPPMessage>();
    var messageSignal: Signal<XMPPMessage, NoError> { get { return self._messageProxy.signal; } };
    @objc internal func xmppStream(sender: XMPPStream!, didReceiveMessage message: XMPPMessage!) {
        if message.isChatMessageWithBody() || ChatState.from(message) != nil {
            self._messageProxy.observer.send(value: message);
        }
    }

    private var _faultSignal = ManagedSignal<ConnectionFault>();
    var fault: Signal<ConnectionFault, NoError> { get { return self._faultSignal.signal; } };
    func xmppStream(_ sender: XMPPStream!, didFailToSend message: XMPPMessage!, error: Error!) {
        self._faultSignal.observer.send(value: .MessageSendFailure(messageBody: message.body()));
    }
}

class XFRosterDelegateProxy: XFDelegateModuleProxy, XMPPRosterDelegate {
    private let _usersProxy = ManagedSignal<[XMPPUser]>();
    var usersSignal: Signal<[XMPPUser], NoError> { get { return self._usersProxy.signal; } }
    @objc internal func xmppRosterDidPopulate(sender: XMPPRosterMemoryStorage!) {
        self._usersProxy.observer.send(value: sender.sortedUsersByName() as! [XMPPUser]!);
    }
    @objc internal func xmppRosterDidChange(sender: XMPPRosterMemoryStorage!) {
        self._usersProxy.observer.send(value: sender.sortedUsersByName() as! [XMPPUser]!);
    }

    /*@objc internal func didUpdateResource(resource: XMPPResourceMemoryStorageObject!, withUser: XMPPResourceMemoryStorageObject!) {
        NSLog("resource updated");
    }*/
}

enum ConnectionFault {
    case ConnectionFailure(error: String);
    case AuthenticationFailure(error: String);
    case MessageSendFailure(messageBody: String);

    func messages() -> (String, String) {
        switch (self) {
        case let .ConnectionFailure(error): return ("Connection error: \(error)", ConnectionFault.errorResolution(error));
        case let .AuthenticationFailure(error): return ("Login error: \(error)", ConnectionFault.errorResolution(error));
        case let .MessageSendFailure(messageBody): return ("Failed to send message. Please try again.", messageBody);
        }
    }

    static func errorResolution(_ error: String) -> String {
        switch error {
        case "The server does not support X-OATH2-GOOGLE authentication.":
            return "Sidetalk has connected to something, but it does not appear to be Google's chat server. Please ensure you have normal access to the Internet, and are not, for instance, behind a wifi access agreement gate.";
        default:
            return "Ensure you have a working internet connection, that you are not behind a firewall or paywall preventing normal access, and try again. If that doesn't work, contact support.";
        }
    }
}

class Connection {
    internal let stream: XMPPStream;
    internal let rosterStorage: XMPPRosterMemoryStorage;
    internal let roster: XMPPRoster;
    internal let reconnect: XMPPReconnect;
    internal let reachability: Reachability?;

    private let messageLog: MessageLog?;

    private var _connectionAttempt = 0;

    private let _streamDelegateProxy: XFStreamDelegateProxy;
    private let _rosterDelegateProxy: XFRosterDelegateProxy;

    init(messageLog: MessageLog? = nil) {
        self.messageLog = messageLog;

        // xmpp logging
        DDLog.add(DDTTYLogger.sharedInstance, with: DDLogLevel.all);
        DDLog.add(STMemoryLogger.sharedInstance, with: DDLogLevel.all);

        // set up network availability detection
        self.reachability = Reachability();

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

    func connect(_ account: String) {
        if stream.isConnected() { stream.disconnect(); }

        self.stream.myJID = XMPPJID(string: account);
        do {
            try stream.connect(withTimeout: TimeInterval(10));
        } catch let error as NSError {
            let innerError = (error.userInfo[NSLocalizedDescriptionKey] as? String) ?? "An unknown error";
            self._faultSignal.observer.send(value: .ConnectionFailure(error: innerError));
        }
    }

    // plumb through proxies
    var connected: Signal<Bool, NoError> { get { return self._streamDelegateProxy.connectSignal; } };
    var authenticated: Signal<Bool, NoError> { get { return self._streamDelegateProxy.authenticatedSignal; } };
    var users: Signal<[XMPPUser], NoError> { get { return self._rosterDelegateProxy.usersSignal.debounce(TimeInterval(0.15), on: QueueScheduler.main); } };

    // centralized error reporting
    internal var _faultSignal = ManagedSignal<ConnectionFault>();
    var fault: Signal<ConnectionFault, NoError> { get { return self._faultSignal.signal; } };

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
    internal func prepare() {
        // if we are authenticated, send initial status and set some stuff up
        self.authenticated.skipRepeats().observeValues { authenticated in
            if authenticated == true {
                self.stream.send(XMPPPresence(name: "presence")); // TODO: this init is silly. this is just the NSXML init.
                self._myself.modify({ _ in Contact(xmppUser: XMPPUserMemoryStorageObject.init(jid: self.stream.myJID), connection: self) });
            }
        }

        // create managed contacts
        self._contactsSignal = self.users.map { users in
            users.map { user in
                self._contactsCache.get(user.jid().bare(), update: { contact in contact.update(user); }, orElse: { self.createContact(user); });
            };
        }

        // add new messages to the appropriate conversations.
        self._streamDelegateProxy.messageSignal.observeValues { rawMessage in
            if let with = self._contactsCache.get(rawMessage.from().bare()) {
                let conversation = with.conversation;

                if rawMessage.isMessageWithBody() {
                    self._latestActivitySignal.observer.send(value: with);
                    let message = Message(from: with, body: rawMessage.body(), at: Date(), conversation: conversation);
                    conversation.addMessage(message);
                    self._latestMessageSignal.observer.send(value: message);
                    self.logMessage(conversation, message);
                }
                if let state = ChatState.from(rawMessage) {
                    self._latestActivitySignal.observer.send(value: with);
                    conversation.setChatState(state);
                }
            } else {
                NSLog("unrecognized user \(rawMessage.from().full())!");
            }
        }

        // if we have a reachability instance, wire up that signal.
        if let reach = self.reachability {
            reach.whenReachable = { _ in self._hasInternet.modify { _ in true; } };
            reach.whenUnreachable = { _ in self._hasInternet.modify { _ in false; } };
            do { try reach.startNotifier(); } catch _ { NSLog("could not start reachability"); }
        }

        // if we get a fault from our delegate, pass it along.
        self._streamDelegateProxy.fault.observeValues { fault in self._faultSignal.observer.send(value: fault) };
    }

    private func createContact(_ user: XMPPUser) -> Contact {
        let result = Contact(xmppUser: user, connection: self);
        if let log = self.messageLog {
            for message in log.messages(forConversation: result.conversation, myself: self.myself_!) {
                result.conversation.addMessage(message);
            }
        }
        return result;
    }

    private func logMessage(_ conversation: Conversation, _ message: Message) {
        if let log = self.messageLog {
            DispatchQueue.global(qos: .background).async(execute: { log.log(message); });
        }
    }

    // send an outbound message in a way that handles the plumbing correctly.
    func sendMessage(to: Contact, _ text: String) {
        let xmlBody = XMLElement(name: "body");
        xmlBody.setStringValue(text, resolvingEntities: false);

        let xmlMessage = XMLElement(name: "message");
        xmlMessage.addAttribute(withName: "type", stringValue: "chat");
        xmlMessage.addAttribute(withName: "to", stringValue: to.inner.jid().full());
        xmlMessage.addChild(xmlBody);

        self.stream.send(xmlMessage);

        let message = Message(from: self.myself_!, body: text, at: Date(), conversation: to.conversation);
        self._latestMessageSignal.observer.send(value: message);
        to.conversation.addMessage(message);
        // TODO: i don't like that this is a separate set of code from the foreign incoming.

        self.logMessage(to.conversation, message);
    }

    func sendChatState(to: Contact, _ state: ChatState) {
        let xmlMessage = XMLElement(name: "message");
        xmlMessage.addAttribute(withName: "type", stringValue: "chat");
        xmlMessage.addAttribute(withName: "to", stringValue: to.inner.jid().full());
        let xmppMessage = XMPPMessage(from: xmlMessage)!;
        switch (state) {
        case .Active: xmppMessage.addActiveChatState();
        case .Composing: xmppMessage.addComposingChatState();
        case .Inactive: xmppMessage.addInactiveChatState();
        case .Paused: xmppMessage.addPausedChatState();
        }
        self.stream.send(xmppMessage);
    }
}

class OAuthConnection: Connection {
    private var _oauth2: OAuth2CodeGrant?;

    override internal func prepare() {
        // if we are xmpp-connected, authenticate
        self.connected.skipRepeats().observeValues { connected in
            if connected == true {
                // need to make a new instance each attempt or else keychain access gets wonky race conditions.
                self._oauth2 = OAuth2CodeGrant(settings: ST.oauth.settings);
                guard let oauth = self._oauth2 else { return };

                oauth.verbose = true;
                oauth.authConfig.authorizeEmbedded = false;
                oauth.authorize(callback: { _, _ in
                    // extract our token.
                    guard let password = oauth.accessToken else { return; }
                    do {
                        try self.stream.authenticate(withGoogleAccessToken: password);
                    } catch let error as NSError {
                        let innerError = (error.userInfo[NSLocalizedDescriptionKey] as? String) ?? "An unknown error";
                        self._faultSignal.observer.send(value: .AuthenticationFailure(error: innerError));
                    }
                });
            }
        }

        super.prepare();
    }
}
