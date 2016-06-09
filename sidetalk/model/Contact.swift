
import Foundation
import XMPPFramework
import ReactiveCocoa
import enum Result.NoError

class Contact: Hashable {
    private var inner: XMPPUser;

    var displayName: String { get { return self.inner.nickname() ?? self.inner.jid().bare(); } };

    var avatarSource: String?; // TODO: eventually use XMPP XEP (confirm gtalk?)

    private var _onlineSignal = ManagedSignal<Bool>();
    var online: Signal<Bool, NoError> { get { return self._onlineSignal.signal; } };
    var onlineOnce: Bool { get { return self.inner.isOnline(); } };

    private var _presenceSignal = ManagedSignal<String?>();
    var presence: Signal<String?, NoError> { get { return self._presenceSignal.signal; } };
    var presenceOnce: String? { get { return self.inner.primaryResource()?.presence()?.show(); } };

    var hashValue: Int { get { return self.inner.jid().hashValue; } };

    init(xmppUser: XMPPUser) {
        // for now, everyone is louis or nick
        if arc4random_uniform(2) == 0 {
            self.avatarSource = "/Users/cxlt/Code/sidetalk/sidetalk/Resources/test1.png";
        } else {
            self.avatarSource = "/Users/cxlt/Code/sidetalk/sidetalk/Resources/test2.jpg";
        }

        self.inner = xmppUser; // init to nil so all props fire
        self.update(xmppUser, forceUpdate: true);
    }

    func update(xmppUser: XMPPUser, forceUpdate: Bool = false) {
        let old = self.inner;
        let new = xmppUser;

        // TODO: really really repetitive
        if forceUpdate || (old.isOnline() != new.isOnline()) { self._onlineSignal.observer.sendNext(new.isOnline()); }
        if forceUpdate || (old.primaryResource()?.presence()?.show() !=
                           new.primaryResource()?.presence()?.show()) { self._presenceSignal.observer.sendNext(new.primaryResource()?.presence()?.show()); }

        self.inner = xmppUser;
    }
}

// base equality on JID. TODO: this is probably an awful idea.
func ==(lhs: Contact, rhs: Contact) -> Bool {
    return lhs.inner.jid().isEqual(rhs.inner.jid());
}
