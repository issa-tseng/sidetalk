
import Foundation;
import Cocoa;
import ReactiveSwift;
import enum Result.NoError;

struct ContactState {
    let chatState: ChatState;
    let lastShown: Date;
    let latestMessage: Message?;
    let active: Bool;
    let selected: Bool;

    static func fromSignals(chatStateSignal: Signal<ChatState, NoError>,
                           lastShownSignal: Signal<Date, NoError>,
                           latestMessageSignal: Signal<Message?, NoError>,
                           activeSignal: Signal<Bool, NoError>,
                           selectedSignal: Signal<Bool, NoError>) -> Signal<ContactState, NoError> {
        // TODO/HACK: hate hate hate hate hate hate
        var chatState = ChatState.Inactive;
        var lastShown = Date.distantPast;
        var latestMessage: Message? = nil;
        var active = false;
        var selected = false;

        let (signal, observer) = Signal<ContactState, NoError>.pipe();
        let update = { (_: Any) -> Void in observer.send(value: ContactState(chatState: chatState, lastShown: lastShown, latestMessage: latestMessage, active: active, selected: selected)); };

        chatStateSignal.observeValues({ x in update(chatState = x) });
        lastShownSignal.observeValues({ x in update(lastShown = x) });
        latestMessageSignal.observeValues({ x in update(latestMessage = x) });
        activeSignal.observeValues({ x in update(active = x) });
        selectedSignal.observeValues({ x in update(selected = x) });

        return signal;
    }
}

class ContactTile : NSView {
    let contact: Contact;
    let size: CGSize;

    private let _showLabel = MutableProperty<Bool>(false);
    var showLabel: Signal<Bool, NoError> { get { return self._showLabel.signal; } };
    var showLabel_: Bool {
        get { return self._showLabel.value; }
        set { self._showLabel.value = newValue; }
    };

    private let _selected = MutableProperty<Bool>(false);
    var selected: Signal<Bool, NoError> { get { return self._selected.signal; } };
    var selected_: Bool {
        get { return self._selected.value; }
        set { self._selected.value = newValue; }
    };

    private let _showStar = MutableProperty<Bool>(false);
    var showStar: Signal<Bool, NoError> { get { return self._showStar.signal; } };
    var showStar_: Bool {
        get { return self._showStar.value; }
        set { self._showStar.value = newValue; }
    };

    let avatarLayer = CAAvatarLayer();
    let outlineLayer = CAShapeLayer();
    let textboxLayer = CAShapeLayer();
    let textLayer = CATextLayer();

    let starLayer = IconLayer();

    let countLayer = CATextLayer();
    let countRingLayer = CAShapeLayer();

    private var _simpleRingObserver: Disposable?;
    private var _conversationView: ConversationView?;

    init(frame: CGRect, contact: Contact) {
        // save props.
        self.contact = contact;
        self.size = frame.size;
        self.avatarLayer.contact = self.contact;

        // actually init.
        super.init(frame: frame);

        // need to set layer-backing here, or else the view just never draws.
        DispatchQueue.main.async(execute: { self.wantsLayer = true; });
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview);


        // now draw everything, and add the layers.
        DispatchQueue.main.async(execute: {
            self.drawAll();

            let layer = self.layer!;
            layer.addSublayer(self.avatarLayer);
            layer.addSublayer(self.outlineLayer);
            layer.addSublayer(self.textboxLayer);
            layer.addSublayer(self.textLayer);
            layer.addSublayer(self.starLayer);
            layer.addSublayer(self.countRingLayer);
            layer.addSublayer(self.countLayer);
        });

        // prep future states
        self.prepare();
    }

    func attachConversation(_ conversationView: ConversationView) {
        // store it. if we already have one we fucked up.
        if self._conversationView != nil { fatalError("you fucked up"); }
        self._conversationView = conversationView;

        // listen to various things.
        let conversation = conversationView.conversation;

        // status ring.
        self._simpleRingObserver?.dispose(); // we're replacing this logic with the full set.
        ContactState.fromSignals(
            chatStateSignal: conversation.chatState,
            lastShownSignal: conversationView.lastShown,
            latestMessageSignal: conversationView.allMessages().filter({ message in message.from == self.contact }).downcastToOptional(),
            activeSignal: conversationView.active,
            selectedSignal: self.selected)
                .observeValues({ all in self.updateRing(all); });

        // unread message count.
        let unread = conversation.latestMessage
            .combineWithDefault(conversationView.lastShown, defaultValue: Date.distantPast).map({ _, shown in shown })
            .combineWithDefault(conversationView.active, defaultValue: false)
            .map({ (shown, active) -> Int in
                if active { return 0; }

                var count = 0; // count this mutably and manually for perf (early exit).
                let startup = (NSApplication.shared.delegate as! AppDelegate).startup;
                for message in conversation.messages {
                    if message.at <= shown { break; }
                    if message.at < startup { break; }
                    if message.from == self.contact { count += 1; }
                }
                return count;
            });

        // update count label and such.
        unread.observeValues { count in
            DispatchQueue.main.async(execute: {
                if count > 0 {
                    self.countLayer.isHidden = false;
                    self.countRingLayer.isHidden = false;

                    let text = NSAttributedString(string: "\(count)", attributes: ST.avatar.countTextAttr);
                    self.countLayer.string = text;
                    let additionalWidth = max(0, text.boundingRect(with: self.frame.size, options: NSString.DrawingOptions()).width - 5.8);
                    self.countRingLayer.path = NSBezierPath(roundedRect: NSRect(origin: NSPoint.zero, size: NSSize(width: 14 + additionalWidth, height: 13)), cornerRadius: 6.5).cgPath;
                } else {
                    self.countLayer.isHidden = true;
                    self.countRingLayer.isHidden = true;
                }
            });
        };
    }

    private func drawAll() {
        // base overall layout on our size.
        let avatarLength = self.size.height - 2;
        let avatarHalf = avatarLength / 2;
        let origin = CGPoint(x: self.size.width - self.size.height + 1, y: 1);

        // init icon.
        let starSize: CGFloat = 16;
        self.starLayer.image = NSImage.init(named: NSImage.Name.init(rawValue: "star"));
        self.starLayer.frame = CGRect(origin: CGPoint(x: self.size.width - starSize, y: 1), size: CGSize(width: starSize, height: starSize));

        // set up avatar layout.
        let avatarSize = CGSize(width: avatarLength, height: avatarLength);
        let avatarBounds = CGRect(origin: origin, size: avatarSize);

        // set up avatar.
        self.avatarLayer.frame = NSRect(origin: origin, size: NSSize(width: avatarLength, height: avatarLength));

        // set up status ring.
        let outlinePath = NSBezierPath(roundedRect: avatarBounds, xRadius: avatarHalf, yRadius: avatarHalf);
        self.outlineLayer.path = outlinePath.cgPath;
        self.outlineLayer.fillColor = NSColor.clear.cgColor;
        self.outlineLayer.strokeColor = ST.avatar.inactiveColor;
        self.outlineLayer.lineWidth = 2;

        // set up text layout.
        let text = NSAttributedString(string: contact.displayName, attributes: ST.avatar.labelTextAttr);
        let textSize = text.size();
        let textOrigin = NSPoint(x: origin.x - 16 - textSize.width, y: origin.y + 3 + textSize.height);
        let textBounds = NSRect(origin: textOrigin, size: textSize);

        // set up text.
        self.textLayer.position = textOrigin;
        self.textLayer.frame = textBounds;
        self.textLayer.contentsScale = NSScreen.main!.backingScaleFactor;
        self.textLayer.string = text;
        self.textLayer.opacity = 0.0;

        // set up textbox.
        let textboxRadius = CGFloat(3);
        let textboxPath = NSBezierPath(roundedRect: textBounds.insetBy(dx: -6, dy: -2), xRadius: textboxRadius, yRadius: textboxRadius);
        self.textboxLayer.path = textboxPath.cgPath;
        self.textboxLayer.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor;
        self.textboxLayer.opacity = 0.0;

        // set up message count.
        self.countLayer.frame = NSRect(origin: NSPoint(x: origin.x + 4, y: origin.y + 4), size: NSSize(width: self.size.width, height: 10));
        self.countLayer.contentsScale = NSScreen.main!.backingScaleFactor;
        self.countLayer.isHidden = true;

        self.countRingLayer.isHidden = true;
        self.countRingLayer.frame.origin = NSPoint(x: origin.x, y: origin.y + 2);
    }

    private func prepare() {
        // adjust label opacity based on whether we're being asked to show them
        self.showLabel.observeValues { show in
            DispatchQueue.main.async(execute: {
                if show {
                    self.textLayer.opacity = 1.0;
                    self.textboxLayer.opacity = 1.0;
                } else {
                    self.textLayer.opacity = 0.0;
                    self.textboxLayer.opacity = 0.0;
                }
            });
        }

        // set up the simple version of ring color adjust. this gets overridden when
        // a conversation is attached.
        self._simpleRingObserver = self.selected.observeValues { selected in
            self.updateRing(ContactState(chatState: .Inactive, lastShown: Date.distantPast, latestMessage: nil, active: false, selected: selected));
        };

        // adjust avatar opacity based on composite presence
        self.contact.online.observeValues({ _ in self.updateOpacity(); });
        self.contact.presence.observeValues({ _ in self.updateOpacity(); });
        self.updateOpacity();

        // adjust star layer visibility.
        self.showStar.observeValues({ shown in
            if self.starLayer.isHidden == shown {
                DispatchQueue.main.async(execute: { self.starLayer.isHidden = !shown; });
            }
        });
        self.starLayer.isHidden = !self.showStar_;
    }

    // HACK: here i'm just using rx to trigger the update, then rendering from
    // static status. because either of these signals could very well never fire.
    private func updateOpacity() {
        DispatchQueue.main.async(execute: {
            if self.contact.isSelf() {
                self.avatarLayer.opacity = 0.9;
            } else if self.contact.online_ {
                if self.contact.presence_ == nil {
                    self.avatarLayer.opacity = 0.9;
                } else {
                    self.avatarLayer.opacity = 0.4;
                }
            } else {
                self.avatarLayer.opacity = 0.1;
            }
        });
    }

    private func updateRing(_ all: ContactState) {
        DispatchQueue.main.async(execute: {
            let hasUnread = !all.active && (all.latestMessage != nil) && (all.latestMessage!.at > all.lastShown);
            if all.chatState == .Composing {
                self.setRingColor(all.selected ? ST.avatar.selectedComposingColor : ST.avatar.composingColor);
            } else if hasUnread {
                self.setRingColor(all.selected ? ST.avatar.selectedAttentionColor : ST.avatar.attentionColor);
            } else {
                self.setRingColor(all.selected ? ST.avatar.selectedInactiveColor : ST.avatar.inactiveColor);
            }

            self.outlineLayer.lineWidth = hasUnread ? 3.0 : 2.0;
        });
    }

    private func setRingColor(_ color: CGColor) {
        self.outlineLayer.strokeColor = color;
        self.countRingLayer.fillColor = color;
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
