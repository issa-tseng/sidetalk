
import Foundation
import Cocoa
import ReactiveCocoa
import enum Result.NoError

struct ContactState {
    let chatState: ChatState?;
    let lastShown: NSDate?;
    let latestMessage: Message?;
}

class ContactTile : NSView {
    let contact: Contact;
    let size: CGSize;

    private let _showLabelSignal = ManagedSignal<Bool>();
    private var _showLabel: Bool = false;
    var showLabelSignal: Signal<Bool, NoError> { get { return self._showLabelSignal.signal; } };
    var showLabel: Bool {
        get { return self._showLabel; }
        set {
            self._showLabelSignal.observer.sendNext(newValue);
            self._showLabel = newValue;
        }
    };

    let avatarLayer: CAAvatarLayer
    let outlineLayer: CAShapeLayer
    let textboxLayer: CAShapeLayer
    let textLayer: CATextLayer

    private let composingColor = NSColor.init(red: 0.027, green: 0.785, blue: 0.746, alpha: 0.95).CGColor;
    private let attentionColor = NSColor.init(red: 0.859, green: 0.531, blue: 0.066, alpha: 1.0).CGColor;
    private let inactiveColor = NSColor.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.2).CGColor;

    private var _conversationView: ConversationView?;

    init(frame: CGRect, size: CGSize, contact: Contact) {
        // save props.
        self.contact = contact;
        self.size = size;

        // create layers.
        self.avatarLayer = CAAvatarLayer();
        self.outlineLayer = CAShapeLayer();
        self.textLayer = CATextLayer();
        self.textboxLayer = CAShapeLayer();

        // set up layers.
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

            let layer = self.layer!
            layer.addSublayer(self.avatarLayer);
            layer.addSublayer(self.outlineLayer);
            layer.addSublayer(self.textboxLayer);
            layer.addSublayer(self.textLayer);
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
        conversation.chatState
            .combineWithDefault(conversationView.lastShown, defaultValue: nil)
            .combineWithDefault(conversation.latestMessage.map({ $0 as Message? }), defaultValue: nil)
            .map({ (stateShown, message) in ContactState(chatState: stateShown.0, lastShown: stateShown.1, latestMessage: message); })
            .observeNext { all in
                dispatch_async(dispatch_get_main_queue(), {
                    let hasUnread = all.latestMessage != nil && (all.lastShown == nil || all.latestMessage!.at.isGreaterThan(all.lastShown));
                    if all.chatState == .Composing {
                        self.outlineLayer.strokeColor = self.composingColor;
                    } else if hasUnread {
                        self.outlineLayer.strokeColor = self.attentionColor;
                    } else {
                        self.outlineLayer.strokeColor = self.inactiveColor;
                    }

                    self.outlineLayer.lineWidth = hasUnread ? 4.0 : 2.0;
                });
            }
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
        self.outlineLayer.strokeColor = self.inactiveColor;
        self.outlineLayer.lineWidth = 2;

        // set up text layout.
        let text = NSAttributedString(string: contact.displayName ?? "unknown", attributes: Common.labelTextAttr);
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
    }

    private func prepare() {
        // adjust label opacity based on whether we're being asked to show them
        self.showLabelSignal.observeNext { show in
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

        // adjust avatar opacity based on composite presence
        self.contact.online.combineLatestWith(self.contact.presence).observeNext { (online, presence) in
            dispatch_async(dispatch_get_main_queue(), {
                if online {
                    if presence == nil {
                        self.avatarLayer.opacity = 0.9;
                    } else {
                        self.avatarLayer.opacity = 0.4;
                    }
                } else {
                    self.avatarLayer.opacity = 0.1;
                }
            });
        }
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
