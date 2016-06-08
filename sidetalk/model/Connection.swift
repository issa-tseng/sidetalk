
import Foundation
import XMPPFramework
import SSKeychain
import ReactiveCocoa
import enum Result.NoError

class SignalProxy<T> {
    private let _signal: Signal<T, NoError>;
    private let _observer: Observer<T, NoError>;

    var signal: Signal<T, NoError>! { get { return self._signal; } }
    var observer: Observer<T, NoError>! { get { return self._observer; } }

    init() {
        (self._signal, self._observer) = Signal<T, NoError>.pipe();
    }
}

class XFStreamDelegateProxy: NSObject, XMPPStreamDelegate {
    private let _xmppQueue = dispatch_queue_create("xmppq-stream", nil);
    init(stream: XMPPStream) {
        super.init();
        stream.addDelegate(self, delegateQueue: self._xmppQueue);
    }
    deinit { } // TODO: do i have to release the dispatch queue?

    private let _connectProxy = SignalProxy<Bool>();
    var connectSignal: Signal<Bool, NoError> { get { return self._connectProxy.signal; } }
    @objc internal func xmppStreamDidConnect(sender: XMPPStream!) {
        self._connectProxy.observer.sendNext(true);
    }
    @objc internal func xmppStreamDidDisconnect(sender: XMPPStream!, withError error: NSError!) {
        self._connectProxy.observer.sendNext(false); // TODO: error?
    }
}

class XFRosterDelegateProxy: NSObject, XMPPRosterDelegate {
    private let _xmppQueue = dispatch_queue_create("xmppq-roster", nil);
    init(roster: XMPPRoster) {
        super.init();
        roster.addDelegate(self, delegateQueue: self._xmppQueue);
    }

    private let _usersProxy = SignalProxy<[XMPPUser]!>();
    var usersSignal: Signal<[XMPPUser]!, NoError> { get { return self._usersProxy.signal; } }
    @objc internal func xmppRosterDidPopulate(sender: XMPPRosterMemoryStorage!) {
        self._usersProxy.observer.sendNext(sender.sortedUsersByName() as! [XMPPUser]!);
    }
    @objc internal func xmppRosterDidChange(sender: XMPPRosterMemoryStorage!) {
        self._usersProxy.observer.sendNext(sender.sortedUsersByName() as! [XMPPUser]!);
    }
}

class Connection {
    internal let stream: XMPPStream;
    internal let rosterStorage: XMPPRosterMemoryStorage;
    internal let roster: XMPPRoster;

    private let _streamDelegateProxy: XFStreamDelegateProxy;
    private let _rosterDelegateProxy: XFRosterDelegateProxy;

    init() {
        // xmpp logging
        DDLog.addLogger(DDTTYLogger.sharedInstance(), withLevel: DDLogLevel.All);

        // setup
        self.rosterStorage = XMPPRosterMemoryStorage();
        self.roster = XMPPRoster.init(rosterStorage: self.rosterStorage);

        self.stream = XMPPStream();
        self.stream.myJID = XMPPJID.jidWithString("clint@dontexplain.com");
        self.stream.hostName = "talk.google.com";

        // init proxies
        self._streamDelegateProxy = XFStreamDelegateProxy(stream: self.stream);
        self._rosterDelegateProxy = XFRosterDelegateProxy(roster: self.roster);

        // connect
        self.prepare();
        self.roster.activate(self.stream);
        try! stream.connectWithTimeout(NSTimeInterval(10));
    }

    // plumb through proxies
    var connected: Signal<Bool, NoError> { get { return self._streamDelegateProxy.connectSignal; } }
    var users: Signal<[XMPPUser]!, NoError> { get { return self._rosterDelegateProxy.usersSignal; } }

    // sets up our own reactions to basic xmpp things
    private func prepare() {
        // if we are xmpp-connected, authenticate
        self.connected.observeNext { next in
            if next == true {
                let creds = SSKeychain.passwordForService("Sidetalk", account: "clint@dontexplain.com");
                try! self.stream.authenticateWithPassword(creds);
            }
        }
    }
}
