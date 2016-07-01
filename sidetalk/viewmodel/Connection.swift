
import Foundation
import XMPPFramework
import SSKeychain
import ReactiveCocoa
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
    // TODO: error?
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

    private let _streamDelegateProxy: XFStreamDelegateProxy;
    private let _rosterDelegateProxy: XFRosterDelegateProxy;

    init() {
        // xmpp logging
        DDLog.addLogger(DDTTYLogger.sharedInstance(), withLevel: DDLogLevel.All);

        // setup
        self.rosterStorage = XMPPRosterMemoryStorage();
        self.roster = XMPPRoster.init(rosterStorage: self.rosterStorage);
        self.reconnect = XMPPReconnect();

        self.stream = XMPPStream();
        self.stream.myJID = XMPPJID.jidWithString("clint@dontexplain.com");
        self.stream.hostName = "talk.google.com";

        // init proxies
        self._streamDelegateProxy = XFStreamDelegateProxy(stream: self.stream);
        self._rosterDelegateProxy = XFRosterDelegateProxy(module: self.roster);

        // connect
        self.prepare();
        self.roster.activate(self.stream);
        self.reconnect.activate(self.stream);
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

    // sets up our own reactions to basic xmpp things
    private func prepare() {
        // if we are xmpp-connected, authenticate
        self.connected.observeNext { connected in
            if connected == true {
                let creds = SSKeychain.passwordForService("Sidetalk", account: "clint@dontexplain.com");
                do { try self.stream.authenticateWithPassword(creds); } catch _ {} // we don't care if this fails; it'll retry.
            }
        }

        // if we are authenticated, send initial status and set some stuff up
        self.authenticated.observeNext { authenticated in
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
}
