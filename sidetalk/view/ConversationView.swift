
import Foundation
import ReactiveCocoa
import enum Result.NoError

struct ConversationState {
    var active: Bool;
}

class ConversationView: NSView {
    internal let conversation: Conversation;
    private let width: CGFloat;

    private let messagePadding = CGFloat(2);
    private let messageShown = NSTimeInterval(3.0);

    private let composeHeight = CGFloat(25);
    private let composePadding = CGFloat(6);
    private let bubbleMarginX = CGFloat(4);
    private let bubbleMarginY = CGFloat(4);
    private let bubbleRadius = CGFloat(3);
    private let bubbleColor = NSColor.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.9).CGColor;
    private let calloutSize = CGFloat(4);

    private let bubbleLayer: CAShapeLayer;
    private let calloutLayer: CAShapeLayer;
    private let textField: NSTextField;
    private var _messages = [MessageView]();

    private let _activeSignal = ManagedSignal<Bool>();
    var active: Signal<Bool, NoError> { get { return self._activeSignal.signal; } };

    private let _lastShownSignal = ManagedSignal<NSDate?>();
    var lastShown: Signal<NSDate?, NoError> { get { return self._lastShownSignal.signal; } };
    private var _lastShownOnce: NSDate?;
    var lastShownOnce: NSDate? { get { return self._lastShownOnce; } };

    init(frame: NSRect, width: CGFloat, conversation: Conversation) {
        self.width = width;
        self.conversation = conversation;

        self.bubbleLayer = CAShapeLayer();
        self.calloutLayer = CAShapeLayer();

        self.textField = NSTextField(frame: NSRect(origin: NSPoint(x: self.calloutSize, y: 0), size: NSSize(width: self.width, height: self.composeHeight)).insetBy(dx: bubbleMarginX, dy: bubbleMarginY));

        super.init(frame: frame);
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(newSuperview);

        self.prepare();

        // calc area.
        let composeArea = NSRect(origin: NSPoint(x: calloutSize, y: 0), size: NSSize(width: self.width, height: composeHeight));

        // draw bubble.
        let bubbleRect = composeArea;
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: bubbleRadius, yRadius: bubbleRadius);
        self.bubbleLayer.path = bubblePath.CGPath;
        self.bubbleLayer.fillColor = self.bubbleColor;
        self.bubbleLayer.opacity = 0.0;

        // draw callout.
        let vlineCenter = CGFloat(12.0);
        let calloutPts = NSPointArray.alloc(3);
        calloutPts[0] = NSPoint(x: calloutSize, y: vlineCenter + calloutSize);
        calloutPts[1] = NSPoint(x: 0, y: vlineCenter);
        calloutPts[2] = NSPoint(x: calloutSize, y: vlineCenter - calloutSize);
        let calloutPath = NSBezierPath();
        calloutPath.appendBezierPathWithPoints(calloutPts, count: 3);
        self.calloutLayer.path = calloutPath.CGPath;
        self.calloutLayer.fillColor = self.bubbleColor;
        self.calloutLayer.opacity = 0.0;

        // set up textfield.
        self.textField.backgroundColor = NSColor.clearColor();
        self.textField.bezeled = false;
        self.textField.focusRingType = NSFocusRingType.None;
        self.textField.font = NSFont.systemFontOfSize(12);
        self.textField.lineBreakMode = .ByTruncatingTail;
        self.textField.alphaValue = 0.0;

        // add layers.
        self.layer!.addSublayer(self.bubbleLayer);
        self.layer!.addSublayer(self.calloutLayer);
        self.addSubview(self.textField);
    }

    private func prepare() {
        self.conversation.latestMessage.observeNext { message in
            self._messages.insert(self.drawMessage(message), atIndex: 0);
        }

        let scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "delayed-messages-conversationview");
        let delayedMessage = self.conversation.latestMessage.delay(self.messageShown, onScheduler: scheduler);

        delayedMessage
            .combineWithDefault(self.active, defaultValue: false).map({ message, active in active })
            .map({ active in ConversationState(active: active) })
            .combinePrevious(ConversationState(active: false))
            .observeNext({ lastState, thisState in self.relayout(lastState, thisState); });

        let keyTracker = Impulse.track(Key);
        GlobalInteraction.sharedInstance.keyPress
            .combineWithDefault(self.active, defaultValue: false)
            .observeNext { wrappedKey, active in
                let key = keyTracker.extract(wrappedKey);
                if active && key == .Return && self.textField.stringValue != "" {
                    self.conversation.sendMessage(self.textField.stringValue);
                    self.textField.stringValue = "";
                }
            }
    }

    private func drawMessage(message: Message) -> MessageView {
        let view = MessageView(
            frame: NSRect(origin: NSPoint(x: 0, y: composeHeight + composePadding), size: self.frame.size),
            width: self.width,
            message: message,
            conversation: self.conversation);

        dispatch_async(dispatch_get_main_queue(), {
            self.addSubview(view);

            // fade in once.
            let anim = CABasicAnimation.init(keyPath: "opacity");
            anim.fromValue = 0.0;
            anim.toValue = 1.0;
            anim.duration = NSTimeInterval(0.1);
            view.layer!.addAnimation(anim, forKey: "message-fade");

            // move on up. just move on up.
            if self._messages.count > 1 {
                let height = view.outerHeight;
                for (idx, oldView) in self._messages.enumerate() {
                    if idx == 0 { continue; }
                    if idx == 1 { oldView.removeCallout(); }
                    oldView.setFrameOrigin(NSPoint(x: oldView.frame.origin.x, y: oldView.frame.origin.y + height + self.messagePadding));
                }
            }
        });
        return view;
    }

    func activate() {
        let now = NSDate();
        self._lastShownOnce = now;
        self._lastShownSignal.observer.sendNext(now);
        self._activeSignal.observer.sendNext(true);
    }
    func deactivate() { self._activeSignal.observer.sendNext(false); }

    // kind of a misnomer; this doesn't lay anything out at all. it just controls visibility.
    private func relayout(lastState: ConversationState, _ thisState: ConversationState) {
        NSLog("conversation relayout for \(self.conversation.with.displayName)");

        dispatch_async(dispatch_get_main_queue(), {
            let now = NSDate();
            if !lastState.active && thisState.active {
                // show all messages (unless they're already shown).
                for (idx, view) in self._messages.enumerate() {
                    if view.message.at.dateByAddingTimeInterval(self.messageShown).isLessThan(now) {
                        let anim = CABasicAnimation.init(keyPath: "opacity");
                        anim.fromValue = 0.0;
                        anim.toValue = 1.0;
                        anim.duration = NSTimeInterval(0.1 + (0.07 * Double(idx)));
                        view.layer!.removeAnimationForKey("message-fade");
                        view.layer!.addAnimation(anim, forKey: "message-fade");
                        view.layer!.opacity = 1.0;
                    }
                }

                // show compose area.
                self.bubbleLayer.opacity = 1.0;
                self.calloutLayer.opacity = 1.0;
                self.textField.alphaValue = 1.0;
                self.window!.makeFirstResponder(self.textField);
            } else if lastState.active && !thisState.active {
                // hide all messages.
                for (idx, view) in self._messages.enumerate() {
                    let anim = CABasicAnimation.init(keyPath: "opacity");
                    anim.fromValue = 1.0;
                    anim.toValue = 0.0;
                    anim.duration = NSTimeInterval(0.2 + (0.04 * Double(idx)));
                    view.layer!.removeAnimationForKey("message-fade");
                    view.layer!.addAnimation(anim, forKey: "message-fade");
                    view.layer!.opacity = 0.0;

                    // hide compose area.
                    self.bubbleLayer.opacity = 0.0;
                    self.calloutLayer.opacity = 0.0;
                    self.textField.alphaValue = 0.0;
                }
            } else if !thisState.active {
                // hide individual messages that may have been shown on receipt.
                for view in self._messages {
                    if view.message.at.dateByAddingTimeInterval(self.messageShown).isLessThanOrEqualTo(now) {
                        if view.layer!.opacity != 0.0 {
                            let anim = CABasicAnimation.init(keyPath: "opacity");
                            anim.fromValue = 1.0;
                            anim.toValue = 0.0;
                            anim.duration = NSTimeInterval(0.1);
                            view.layer!.removeAnimationForKey("message-fade");
                            view.layer!.addAnimation(anim, forKey: "message-fade");
                            view.layer!.opacity = 0.0;
                        }
                    } else {
                        // no point in running through the rest.
                        break;
                    }
                }
            }
        });
    }

    required init(coder: NSCoder) {
        fatalError("fauxcoder");
    }
}
