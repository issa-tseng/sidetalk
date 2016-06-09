
import Foundation
import XMPPFramework
import ReactiveCocoa
import enum Result.NoError

class AvatarDelegate: NSObject, XMPPvCardTempModuleDelegate {
    private let _withResult: (NSImage!) -> ();
    init(withResult: (NSImage!) -> ()) { self._withResult = withResult; }

    @objc internal func xmppvCardTempModule(vCardTempModule: XMPPvCardTempModule!, didReceivevCardTemp vCardTemp: XMPPvCardTemp!, forJID jid: XMPPJID!) {
        let avatarb64 = vCardTemp.elementForName("PHOTO").stringValue;
        if avatarb64 != nil {
            let decoded = NSData.init(base64EncodedString: avatarb64!, options: .IgnoreUnknownCharacters);
            if decoded != nil { self._withResult(NSImage.init(data: decoded!)); };
        }
    }
}

class Contact: Hashable {
    internal var inner: XMPPUser;
    internal let stream: XMPPStream; // TODO: i hate this being here but i'm not sure how else to manage this yet.

    var displayName: String { get { return self.inner.nickname() ?? self.inner.jid().bare(); } };

    private var _onlineSignal = ManagedSignal<Bool>();
    var online: Signal<Bool, NoError> { get { return self._onlineSignal.signal; } };
    var onlineOnce: Bool { get { return self.inner.isOnline(); } };

    private var _presenceSignal = ManagedSignal<String?>();
    var presence: Signal<String?, NoError> { get { return self._presenceSignal.signal; } };
    var presenceOnce: String? { get { return self.inner.primaryResource()?.presence()?.show(); } };

    private var _avatarSignal: SignalProducer<NSImage?, NoError>?;
    var avatar: SignalProducer<NSImage?, NoError> { get { return self._avatarSignal!; } };

    var hashValue: Int { get { return self.inner.jid().hashValue; } };

    init(xmppUser: XMPPUser, xmppStream: XMPPStream) {
        self.inner = xmppUser;
        self.stream = xmppStream;
        self.update(xmppUser, forceUpdate: true);

        self.prepare();
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

    func prepare() {
        self._avatarSignal = SignalProducer { observer, disposable in
            observer.sendNext(nil); // start with fallback avvy

            let backgroundThread = dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0);
            dispatch_async(backgroundThread, {
                // TODO: lots of instantiation and shit. overhead?
                let vcardTemp = XMPPvCardTempModule(vCardStorage: XMPPvCardCoreDataStorage.sharedInstance());
                let vcardAvatar = XMPPvCardAvatarModule(vCardTempModule: vcardTemp);

                vcardTemp.activate(self.stream);
                vcardAvatar.activate(self.stream);

                let photoData = vcardAvatar.photoDataForJID(self.inner.jid());
                if photoData == nil {
                    // we don't have it already cached, so go fetch it
                    let delegate = AvatarDelegate(withResult: { image in observer.sendNext(image); });
                    vcardAvatar.addDelegate(delegate, delegateQueue: backgroundThread)
                    vcardTemp.fetchvCardTempForJID(self.inner.jid(), ignoreStorage: true);
                } else {
                    observer.sendNext(NSImage.init(data: photoData));
                }
            });
        }
    }
}

// base equality on JID. TODO: this is probably an awful idea.
func ==(lhs: Contact, rhs: Contact) -> Bool {
    return lhs.inner.jid().isEqual(rhs.inner.jid());
}
