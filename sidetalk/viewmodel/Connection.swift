
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
    var users: Signal<[XMPPUser], NoError> { get { return self._rosterDelegateProxy.usersSignal.throttle(NSTimeInterval(0.15), onScheduler: QueueScheduler.mainQueueScheduler); } };

    // own user
    private var _myselfSignal = ManagedSignal<XMPPUser?>();
    var myself: Signal<XMPPUser?, NoError> { get { return self._myselfSignal.signal; } };

    // managed contacts (impl in prepare())
    private var _contactsCache = QuickCache<XMPPJID, Contact>();
    private var _contactsSignal: Signal<[Contact], NoError>?;
    var contacts: Signal<[Contact], NoError> { get { return self._contactsSignal!; } };

    // sets up our own reactions to basic xmpp things
    private func prepare() {
        // if we are xmpp-connected, authenticate
        self.connected.observeNext { connected in
            if connected == true {
                let creds = SSKeychain.passwordForService("Sidetalk", account: "clint@dontexplain.com");
                try! self.stream.authenticateWithPassword(creds);
            }
        }

        // if we are authenticated, send initial status and set some stuff up
        self.authenticated.observeNext { authenticated in
            if authenticated == true {
                self.stream.sendElement(XMPPPresence(name: "presence")); // TODO: this init is silly. this is just the NSXML init.
                self._myselfSignal.observer.sendNext(XMPPUserMemoryStorageObject.init(JID: self.stream.myJID));
            }
        }

        // create managed contacts
        self._contactsSignal = self.users.map { users in
            users.map { user in
                self._contactsCache.get(user.jid(), update: { contact in contact.update(user); }, orElse: { Contact(xmppUser: user, xmppStream: self.stream); });
            };
        }
    }
}
