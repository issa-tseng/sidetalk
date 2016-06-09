
import Foundation
import XMPPFramework

class Contact: Hashable {
    private var inner: XMPPUser;

    var displayName: String { get { return self.inner.nickname() ?? self.inner.jid().bare(); } };

    var avatarSource: String?; // TODO: eventually use XMPP XEP (confirm gtalk?)

    var online: Bool { get { return self.inner.isOnline(); } }

    var presence: String? { get { return self.inner.primaryResource()?.presence()?.show(); } };

    var hashValue: Int { get { return self.inner.jid().hashValue; } };

    init(xmppUser: XMPPUser) {
        self.inner = xmppUser;

        // for now, everyone is louis or nick
        if arc4random_uniform(2) == 0 {
            self.avatarSource = "/Users/cxlt/Code/sidetalk/sidetalk/Resources/test1.png";
        } else {
            self.avatarSource = "/Users/cxlt/Code/sidetalk/sidetalk/Resources/test2.jpg";
        }
    }

    func update(xmppUser: XMPPUser) {
        self.inner = xmppUser;
    }
}

// base equality on JID. TODO: this is probably an awful idea.
func ==(lhs: Contact, rhs: Contact) -> Bool {
    return lhs.inner.jid().isEqual(rhs.inner.jid());
}
