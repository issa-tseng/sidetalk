
import Foundation
import Cocoa
import ReactiveCocoa
import enum Result.NoError

struct ContactState {
    let chatState: ChatState?;
    let lastShown: NSDate?;
    let latestMessage: Message?;
    let active: Bool;
    let selected: Bool;
}

class ContactTile : NSView {
    let contact: Contact;
    let size: CGSize;

    private let _showLabel = MutableProperty<Bool>(false);
    var showLabel: Signal<Bool, NoError> { get { return self._showLabel.signal; } };
    var showLabel_: Bool {
        get { return self._showLabel.value; }
        set { self._showLabel.modify { _ in newValue }; }
    };

    private let _selected = MutableProperty<Bool>(false);
    var selected: Signal<Bool, NoError> { get { return self._selected.signal; } };
    var selected_: Bool {
        get { return self._selected.value; }
        set { self._selected.modify { _ in newValue }; }
    };

    let avatarLayer = CAAvatarLayer();
    let outlineLayer = CAShapeLayer();
    let textboxLayer = CAShapeLayer();
    let textLayer = CATextLayer();

    let countLayer = CATextLayer();
    let countRingLayer = CAShapeLayer();

    private var _simpleRingObserver: Disposable?;
    private var _conversationView: ConversationView?;

    init(frame: CGRect, size: CGSize, contact: Contact) {
        // save props.
        self.contact = contact;
        self.size = size;
        self.avatarLayer.contact = self.contact;

        // actually init.
        super.init(frame: frame);
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(newSuperview);

        // now draw everything, and add the layers.
        dispatch_async(dispatch_get_main_queue(), {
            self.drawAll();

            let layer = self.layer!;
            layer.addSublayer(self.avatarLayer);
            layer.addSublayer(self.outlineLayer);
            layer.addSublayer(self.textboxLayer);
            layer.addSublayer(self.textLayer);
            layer.addSublayer(self.countRingLayer);
            layer.addSublayer(self.countLayer);
        });

        // prep future states
        self.prepare();
    }

    func attachConversation(conversationView: ConversationView) {
        // store it. if we already have one we fucked up.
        if self._conversationView != nil { fatalError("you fucked up"); }
        self._conversationView = conversationView;

        // listen to various things.
        let conversation = conversationView.conversation;

        // status ring.
        self._simpleRingObserver?.dispose(); // we're replacing this logic with the full set.
        conversation.chatState
            .combineWithDefault(conversationView.lastShown, defaultValue: NSDate.distantPast())
            .combineWithDefault(conversationView.allMessages().filter({ message in message.from == self.contact }).downcastToOptional(), defaultValue: nil)
            .combineWithDefault(conversationView.active, defaultValue: false)
            .combineWithDefault(self.selected, defaultValue: false)
            .map({ (tuple, selected) in ContactState(chatState: tuple.0.0.0, lastShown: tuple.0.0.1, latestMessage: tuple.0.1, active: tuple.1, selected: selected); })
            .observeNext { all in self.updateRing(all) }

        // unread message count.
        let unread = conversation.latestMessage
            .combineWithDefault(conversationView.lastShown, defaultValue: NSDate.distantPast()).map({ _, shown in shown })
            .combineWithDefault(conversationView.active, defaultValue: false)
            .map({ (shown, active) -> Int in
                if active { return 0; }

                var count = 0; // count this mutably and manually for perf (early exit).
                for message in conversation.messages {
                    if message.at.isLessThanOrEqualTo(shown) { break; }
                    if message.from == self.contact { count += 1; }
                }
                return count;
            });

        // update count label and such.
        unread.observeNext { count in
            dispatch_async(dispatch_get_main_queue(), {
                if count > 0 {
                    self.countLayer.hidden = false;
                    self.countRingLayer.hidden = false;

                    let text = NSAttributedString(string: "\(count)", attributes: ST.avatar.countTextAttr);
                    self.countLayer.string = text;
                    let additionalWidth = max(0, text.boundingRectWithSize(self.frame.size, options: NSStringDrawingOptions()).width - 5.8);
                    self.countRingLayer.path = NSBezierPath(roundedRect: NSRect(origin: NSPoint.zero, size: NSSize(width: 14 + additionalWidth, height: 13)), cornerRadius: 6.5).CGPath;
                } else {
                    self.countLayer.hidden = true;
                    self.countRingLayer.hidden = true;
                }
            });
        };
    }

    private func drawAll() {
        // base overall layout on our size.
        let avatarLength = self.size.height - 2;
        let avatarHalf = avatarLength / 2;
        let origin = CGPoint(x: self.size.width - self.size.height + 1, y: 1);

        // set up avatar layout.
        let avatarSize = CGSize(width: avatarLength, height: avatarLength);
        let avatarBounds = CGRect(origin: origin, size: avatarSize);

        // set up avatar.
        self.avatarLayer.frame = NSRect(origin: origin, size: NSSize(width: avatarLength, height: avatarLength));

        // set up status ring.
        let outlinePath = NSBezierPath(roundedRect: avatarBounds, xRadius: avatarHalf, yRadius: avatarHalf);
        self.outlineLayer.path = outlinePath.CGPath;
        self.outlineLayer.fillColor = NSColor.clearColor().CGColor;
        self.outlineLayer.strokeColor = ST.avatar.inactiveColor;
        self.outlineLayer.lineWidth = 2;

        // set up text layout.
        let text = NSAttributedString(string: contact.displayName ?? "unknown", attributes: ST.avatar.labelTextAttr);
        let textSize = text.size();
        let textOrigin = NSPoint(x: origin.x - 16 - textSize.width, y: origin.y + 3 + textSize.height);
        let textBounds = NSRect(origin: textOrigin, size: textSize);

        // set up text.
        self.textLayer.position = textOrigin;
        self.textLayer.frame = textBounds;
        self.textLayer.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;
        self.textLayer.string = text;
        self.textLayer.opacity = 0.0;

        // set up textbox.
        let textboxRadius = CGFloat(3);
        let textboxPath = NSBezierPath(roundedRect: textBounds.insetBy(dx: -6, dy: -2), xRadius: textboxRadius, yRadius: textboxRadius);
        self.textboxLayer.path = textboxPath.CGPath;
        self.textboxLayer.fillColor = NSColor.blackColor().colorWithAlphaComponent(0.5).CGColor;
        self.textboxLayer.opacity = 0.0;

        // set up message count.
        self.countLayer.frame = NSRect(origin: NSPoint(x: origin.x + 4, y: origin.y + 4), size: NSSize(width: self.size.width, height: 10));
        self.countLayer.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;
        self.countLayer.hidden = true;

        self.countRingLayer.hidden = true;
        self.countRingLayer.frame.origin = NSPoint(x: origin.x, y: origin.y + 2);
    }

    private func prepare() {
        // adjust label opacity based on whether we're being asked to show them
        self.showLabel.observeNext { show in
            dispatch_async(dispatch_get_main_queue(), {
                if show {
                    self.textLayer.opacity = 1.0;
                    self.textboxLayer.opacity = 1.0;
                } else {
                    self.textLayer.opacity = 0.0;
                    self.textboxLayer.opacity = 0.0;
                }
            });
        }

        // set up the simple version of ring color adjust. this gets overriden when
        // a conversation is attached.
        self._simpleRingObserver = self.selected.observeNext { selected in
            self.updateRing(ContactState(chatState: nil, lastShown: NSDate.distantPast(), latestMessage: nil, active: false, selected: selected));
        };

        // adjust avatar opacity based on composite presence
        self.contact.online.observeNext({ _ in self.updateOpacity(); });
        self.contact.presence.observeNext({ _ in self.updateOpacity(); });
        self.updateOpacity();
    }

    // HACK: here i'm just using rx to trigger the update, then rendering from
    // static status. because either of these signals could very well never fire.
    private func updateOpacity() {
        dispatch_async(dispatch_get_main_queue(), {
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

    private func updateRing(all: ContactState) {
        dispatch_async(dispatch_get_main_queue(), {
            let hasUnread = !all.active && (all.latestMessage != nil) && all.latestMessage!.at.isGreaterThan(all.lastShown);
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

    private func setRingColor(color: CGColor) {
        self.outlineLayer.strokeColor = color;
        self.countRingLayer.fillColor = color;
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
