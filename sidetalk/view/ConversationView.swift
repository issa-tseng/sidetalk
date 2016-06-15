
import Foundation
import ReactiveCocoa
import enum Result.NoError

class MessageView: NSView {
    private let textView: NSTextView;
    private let bubbleLayer: CAShapeLayer;
    private var calloutLayer: CAShapeLayer?;

    private let textWidth = CGFloat(250);
    private let width: CGFloat;

    private var _outerHeight: CGFloat?;
    var outerHeight: CGFloat { get { return self._outerHeight ?? 0; } };

    private let bubbleColor = NSColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 0.85).CGColor;
    private let bubbleMarginX = CGFloat(4);
    private let bubbleMarginY = CGFloat(4);
    private let bubbleRadius = CGFloat(3);

    private let calloutSize = CGFloat(4);

    private let message: Message;

    init(frame: NSRect, width: CGFloat, message: Message) {
        self.textView = NSTextView(frame: NSRect(origin: NSPoint.zero, size: NSSize(width: textWidth, height: 0)));
        self.bubbleLayer = CAShapeLayer();
        self.calloutLayer = CAShapeLayer();
        self.width = width;
        self.message = message;

        super.init(frame: frame);
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        super.viewWillMoveToSuperview(newSuperview);
        self.wantsLayer = true;

        // render text view.
        self.textView.verticallyResizable = true;
        self.textView.string = self.message.body;
        self.textView.drawsBackground = false;
        self.textView.editable = false;
        self.textView.textColor = NSColor.whiteColor();
        self.textView.font = NSFont.systemFontOfSize(12);
        self.textView.sizeToFit();

        // calculate text/bubble frame.
        let size = self.textView.layoutManager!.usedRectForTextContainer(self.textView.textContainer!).size;
        let origin = NSPoint(x: self.width - bubbleMarginX - size.width, y: bubbleMarginY);
        self.textView.setFrameOrigin(origin);

        // draw bubble.
        let bubbleRect = NSRect(origin: origin, size: size).insetBy(dx: -bubbleMarginX, dy: -bubbleMarginY);
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: bubbleRadius, yRadius: bubbleRadius);
        self.bubbleLayer.path = bubblePath.CGPath;
        self.bubbleLayer.fillColor = self.bubbleColor;

        // draw callout.
        let rightEdge = origin.x + size.width + bubbleMarginX;
        let vlineCenter = origin.y + 7.0;
        let calloutPts = NSPointArray.alloc(3);
        calloutPts[0] = NSPoint(x: rightEdge, y: vlineCenter + calloutSize);
        calloutPts[1] = NSPoint(x: rightEdge + calloutSize, y: vlineCenter);
        calloutPts[2] = NSPoint(x: rightEdge, y: vlineCenter - calloutSize);
        let calloutPath = NSBezierPath();
        calloutPath.appendBezierPathWithPoints(calloutPts, count: 3);
        self.calloutLayer!.path = calloutPath.CGPath;
        self.calloutLayer!.fillColor = self.bubbleColor;

        // add everything.
        self.layer!.addSublayer(self.calloutLayer!);
        self.layer!.addSublayer(self.bubbleLayer);
        self.addSubview(self.textView);

        // remember outer height for other calculations.
        self._outerHeight = bubbleRect.height;

        /*//self.layerUsesCoreImageFilters = true;

        let blurFilter = CIFilter(name: "CIGaussianBlur")!;
        blurFilter.setDefaults();
        blurFilter.setValue(NSNumber(double: 8.0), forKey: "inputRadius");
        self.bubbleLayer.backgroundFilters = [ blurFilter ];
        //self.bubbleLayer.needsDisplayOnBoundsChange = true;
        self.bubbleLayer.setNeedsDisplay();*/
    }

    func removeCallout() {
        self.calloutLayer!.removeFromSuperlayer();
        self.calloutLayer = nil;
    }

    required init(coder: NSCoder) {
        fatalError("vocoder");
    }
}

struct ConversationState {
    var active: Bool;
}

class ConversationView: NSView {
    private let conversation: Conversation;
    private let width: CGFloat;

    private let messagePadding = CGFloat(2);
    private let messageShown = NSTimeInterval(3.0);

    private var _messages = [MessageView]();

    private let _activeSignal = ManagedSignal<Bool>();
    var active: Signal<Bool, NoError> { get { return self._activeSignal.signal; } };

    init(frame: NSRect, width: CGFloat, conversation: Conversation) {
        self.width = width;
        self.conversation = conversation;

        super.init(frame: frame);
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(newSuperview);

        self.prepare();
    }

    private func prepare() {
        self.conversation.latestMessage.observeNext { message in
            self._messages.insert(self.drawMessage(message), atIndex: 0);
        }

        let scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "delayed-messages");
        let delayedMessage = self.conversation.latestMessage.delay(self.messageShown, onScheduler: scheduler);

        delayedMessage
            .combineWithDefault(self.active, defaultValue: false).map({ message, active in active })
            .map({ active in ConversationState(active: active) })
            .combinePrevious(ConversationState(active: false))
            .observeNext({ lastState, thisState in self.relayout(lastState, thisState); });
    }

    private func drawMessage(message: Message) -> MessageView {
        let view = MessageView(frame: NSRect(origin: NSPoint.zero, size: self.frame.size), width: self.width, message: message);
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

    func activate() { self._activeSignal.observer.sendNext(true); }
    func deactivate() { self._activeSignal.observer.sendNext(false); }

    // kind of a misnomer; this doesn't lay anything out at all. it just controls visibility.
    private func relayout(lastState: ConversationState, _ thisState: ConversationState) {
        NSLog("conversation relayout for \(self.conversation.with.displayName)");

        dispatch_async(dispatch_get_main_queue(), {
            let now = NSDate();
            if !lastState.active && thisState.active {
                // show all messages (unless they're already shown).
                for (idx, view) in self._messages.enumerate() {
                    if view.message.at.dateByAddingTimeInterval(self.messageShown).isGreaterThanOrEqualTo(now) {
                        let anim = CABasicAnimation.init(keyPath: "opacity");
                        anim.fromValue = 0.0;
                        anim.toValue = 1.0;
                        anim.duration = NSTimeInterval(0.1 + (0.02 * Double(idx)));
                        view.layer!.removeAnimationForKey("message-fade");
                        view.layer!.addAnimation(anim, forKey: "message-fade");
                        view.layer!.opacity = 1.0;
                    }
                }
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
                }
            } else if !thisState.active {
                // hide individual messages that may have been shown on receipt.
                for view in self._messages {
                    if view.message.at.dateByAddingTimeInterval(self.messageShown).isLessThanOrEqualTo(now) {
                        if view.layer!.opacity != 0.0 {
                            let anim = CABasicAnimation.init(keyPath: "opacity");
                            anim.fromValue = 1.0;
                            anim.toValue = 0.0;
                            anim.duration = NSTimeInterval(0.4);
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
