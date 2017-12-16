
import Foundation;
import XMPPFramework;
import ReactiveSwift;
import enum Result.NoError;

enum Presence {
    case Online, Offline, Away, Busy, Invisible, None;
}

class AvatarDelegate: NSObject, XMPPvCardTempModuleDelegate {
    private let _withResult: (NSImage!) -> ();
    init(withResult: @escaping (NSImage!) -> ()) { self._withResult = withResult; }

    @objc internal func xmppvCardTempModule(vCardTempModule: XMPPvCardTempModule!, didReceivevCardTemp vCardTemp: XMPPvCardTemp!, forJID jid: XMPPJID!) {
        let avatarb64 = vCardTemp.forName("PHOTO").stringValue;
        if avatarb64 != nil {
            let decoded = Data.init(base64Encoded: avatarb64!, options: .ignoreUnknownCharacters);
            if decoded != nil { self._withResult(NSImage.init(data: decoded!)); };
        }
    }
}

class Contact: Hashable {
    internal var inner: XMPPUser;
    internal let connection: Connection; // TODO: i hate this being here but i'm not sure how else to manage this yet.

    var displayName: String { get { return self.inner.nickname() ?? self.inner.jid().bare(); } };

    var initials: String { get {
        let full = self.displayName;
        let initialsRegex = try! NSRegularExpression(pattern: "^(.)[^ ._-]*[ ._-](.)", options: .useUnicodeWordBoundaries);
        let initials = initialsRegex.matches(in: full, options: NSRegularExpression.MatchingOptions(), range: NSRange());

        if initials.count > 1 {
            let nsFull = full as NSString;
            return initials.map({ result in nsFull.substring(with: result.range); }).joined(separator: "");
        } else {
            return String(full.prefix(upTo: full.index(full.startIndex, offsetBy: 2)));
        }
    } };

    private var _onlineSignal = ManagedSignal<Bool>();
    var online: Signal<Bool, NoError> { get { return self._onlineSignal.signal; } };
    var online_: Bool { get { return self.inner.isOnline(); } };

    private var _presenceSignal = ManagedSignal<String?>();
    var presence: Signal<String?, NoError> { get { return self._presenceSignal.signal; } };
    var presence_: String? { get { return self.inner.primaryResource()?.presence()?.show(); } };

    private var _avatarSignal: SignalProducer<NSImage?, NoError>?;
    var avatar: SignalProducer<NSImage?, NoError> { get { return self._avatarSignal!; } };

    private var _conversation: Conversation?;
    var conversation: Conversation { get { return self._conversation!; } };

    var hashValue: Int { get { return self.inner.jid().hashValue; } };

    init(xmppUser: XMPPUser, connection: Connection) {
        self.inner = xmppUser;
        self.connection = connection;
        self._conversation = Conversation(self, connection: connection);
        self.update(xmppUser, forceUpdate: true);

        self.prepare();
    }

    func update(_ xmppUser: XMPPUser, forceUpdate: Bool = false) {
        let old = self.inner;
        let new = xmppUser;

        // TODO: really really repetitive
        if forceUpdate || (old.isOnline() != new.isOnline()) { self._onlineSignal.observer.send(value: new.isOnline()); }
        if forceUpdate || (old.primaryResource()?.presence()?.show() !=
            new.primaryResource()?.presence()?.show()) { self._presenceSignal.observer.send(value: new.primaryResource()?.presence()?.show()); }

        self.inner = xmppUser;
    }

    func isSelf() -> Bool { return self == self.connection.myself_; }

    private func prepare() {
        self._avatarSignal = SignalProducer { observer, disposable in
            observer.send(value: nil); // start with fallback avvy

            // cold signal to fetch the avatar if asked for.
            let backgroundThread = DispatchQueue.global(qos: .background);
            backgroundThread.async(execute: {
                // TODO: lots of instantiation and shit. overhead?
                let vcardTemp = XMPPvCardTempModule(vCardStorage: XMPPvCardCoreDataStorage.sharedInstance())!;
                let vcardAvatar = XMPPvCardAvatarModule(vCardTempModule: vcardTemp)!;

                let photoData = vcardAvatar.photoData(for: self.inner.jid());
                if photoData == nil {
                    // we don't have it already cached, so go fetch it
                    vcardTemp.activate(self.connection.stream);
                    vcardAvatar.activate(self.connection.stream);

                    vcardAvatar.addDelegate(AvatarDelegate(withResult: { image in observer.send(value: image); }), delegateQueue: backgroundThread);
                    vcardTemp.fetchvCardTemp(for: self.inner.jid(), ignoreStorage: true);
                } else {
                    observer.send(value: NSImage.init(data: photoData!));
                }
            });
        }
    }
}

// base equality on JID. TODO: this is probably an awful idea.
func ==(lhs: Contact, rhs: Contact) -> Bool {
    return lhs.inner.jid().isEqual(rhs.inner.jid());
}
