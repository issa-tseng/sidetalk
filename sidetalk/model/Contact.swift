
import Foundation
import XMPPFramework

class Contact {
    private let inner: XMPPUser;
    var displayName: String? { get { return self.inner.nickname(); } }
    var avatarSource: String?; // TODO: eventually use XMPP XEP (confirm gtalk?)

    init(xmppUser: XMPPUser) {
        self.inner = xmppUser;

        // for now, everyone is louis or nick
        if arc4random_uniform(2) == 0 {
            self.avatarSource = "/Users/cxlt/Code/sidetalk/sidetalk/Resources/test1.png";
        } else {
            self.avatarSource = "/Users/cxlt/Code/sidetalk/sidetalk/Resources/test2.jpg";
        }
    }
}
