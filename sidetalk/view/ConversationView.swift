
import Foundation
import ReactiveCocoa
import enum Result.NoError

class ConversationView: NSView {
    internal let conversation: Conversation;
    private let width: CGFloat;

    private let messagePadding = CGFloat(2);
    private let messageShown = NSTimeInterval(5.0);
    private let sendLockout = NSTimeInterval(0.1);

    private let composeHeight = CGFloat(80);
    private let composePadding = CGFloat(6);
    private let bubbleMarginX = CGFloat(4);
    private let bubbleMarginY = CGFloat(4);
    private let bubbleRadius = CGFloat(3);
    private let bubbleColor = NSColor.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.9).CGColor;
    private let calloutSize = CGFloat(4);
    private let composeTextSize = CGFloat(12);

    private let bubbleLayer: CAShapeLayer;
    private let calloutLayer: CAShapeLayer;
    private let textField: NSTextField;
    private var _messages = [MessageView]();

    private var _initiallyActivated = false;
    private let _active = MutableProperty<Bool>(false);
    var active: Signal<Bool, NoError> { get { return self._active.signal; } };

    private let _lastShown = MutableProperty<NSDate>(NSDate.distantPast());
    var lastShown: Signal<NSDate, NoError> { get { return self._lastShown.signal; } };
    var lastShown_: NSDate { get { return self._lastShown.value; } };

    private let _searchLeecher: STTextDelegate;
    var text: Signal<String, NoError> { get { return self._searchLeecher.text; } };

    init(frame: NSRect, width: CGFloat, conversation: Conversation) {
        self.width = width;
        self.conversation = conversation;

        self.bubbleLayer = CAShapeLayer();
        self.calloutLayer = CAShapeLayer();

        self.textField = NSTextField(frame: NSRect(origin: NSPoint(x: self.calloutSize, y: 0), size: NSSize(width: self.width, height: self.composeHeight)).insetBy(dx: bubbleMarginX, dy: bubbleMarginY));

        self._searchLeecher = STTextDelegate(field: self.textField);

        super.init(frame: frame);
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(newSuperview);

        self.prepare();

        // draw bubble.
        self.updateComposeHeight();
        self.bubbleLayer.fillColor = self.bubbleColor;
        self.bubbleLayer.opacity = 0.0;

        // draw callout.
        let vlineCenter = self.composeHeight - CGFloat(13.0);
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
        self.textField.font = NSFont.systemFontOfSize(self.composeTextSize);
        self.textField.lineBreakMode = .ByWordWrapping;
        self.textField.alphaValue = 0.0;

        // add layers.
        self.layer!.addSublayer(self.bubbleLayer);
        self.layer!.addSublayer(self.calloutLayer);
        self.addSubview(self.textField);
    }

    // like conversation#latestMessage, but returns all messages we know about.
    func allMessages() -> Signal<Message, NoError> {
        let managed = ManagedSignal<Message>();

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), {
            for message in self.conversation.messages.reverse() { managed.observer.sendNext(message); }
            self.conversation.latestMessage.observeNext({ message in managed.observer.sendNext(message); });
        });

        return managed.signal;
    }

    private func prepare() {
        let allMessages = self.allMessages();
        allMessages.observeNext { message in self.drawMessage(message) };

        let scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "delayed-messages-conversationview");
        let delayedMessage = allMessages.delay(self.messageShown, onScheduler: scheduler);

        self.active
            .combineWithDefault(delayedMessage.downcastToOptional(), defaultValue: nil).map({ active, _ in active })
            .combineWithDefault(self.conversation.connection.hasInternet, defaultValue: true)
            .combinePrevious((false, true))
            .observeNext({ last, this in self.relayout(last, this); });

        // TODO: it's entirely possible that the better way to do this would be to drop Impulses altogether and
        // simply consume the keystroke entirely within MainView. but for now, bodge it with a delay.
        let keyTracker = Impulse.track(Key);
        GlobalInteraction.sharedInstance.keyPress
            .combineWithDefault(self.active, defaultValue: false)
            .observeNext { wrappedKey, active in
                let key = keyTracker.extract(wrappedKey);

                if !active || self.lastShown_.dateByAddingTimeInterval(self.sendLockout).isGreaterThan(NSDate()) { return; }

                if self.conversation.connection.hasInternet_ && (key == .Return) && (self.textField.stringValue != "") {
                    self.conversation.sendMessage(self.textField.stringValue);
                    self.textField.stringValue = "";
                } else if key == .LineBreak {
                    self.textField.insertText("\n");
                }
            };

        self._active.modify({ _ in self._initiallyActivated });

        self.text.observeNext { _ in self.updateComposeHeight(); };
    }

    private func drawMessage(message: Message) -> MessageView {
        let view = MessageView(
            frame: NSRect(origin: NSPoint(x: 0, y: composeHeight + composePadding), size: self.frame.size),
            width: self.width,
            message: message,
            conversation: self.conversation);
        self._messages.insert(view, atIndex: 0);

        dispatch_async(dispatch_get_main_queue(), {
            self.addSubview(view);

            // fade in once.
            view.alphaValue = 0.0;
            animationWithDuration(0.1, { view.animator().alphaValue = 1.0; });

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
        self._initiallyActivated = true;
        self._lastShown.modify({ _ in NSDate() });
        self._active.modify({ _ in true });
    }

    func deactivate() {
        self._lastShown.modify({ _ in NSDate() });
        self._active.modify({ _ in false });
    }

    // kind of a misnomer; this doesn't lay anything out at all. it just controls visibility.
    private func relayout(lastState: (Bool, Bool), _ thisState: (Bool, Bool)) {
        let (last, _) = lastState;
        let (this, online) = thisState;

        dispatch_async(dispatch_get_main_queue(), {
            // handle messages.
            if !last && this {
                // show all messages. TODO: don't bother to animate offscreen stuff.
                for (idx, view) in self._messages.enumerate() {
                    animationWithDuration(0.1 + (0.07 * Double(idx)), { view.animator().alphaValue = 1.0; });
                }
            } else if last && !this {
                // hide all messages.
                for (idx, view) in self._messages.enumerate() {
                    animationWithDuration(0.2 + (0.04 * Double(idx)), { view.animator().alphaValue = 0.0; })
                }
            } else if !this {
                // hide individual messages that may have been shown on receipt.
                let now = NSDate();
                for view in self._messages {
                    if view.message.at.dateByAddingTimeInterval(self.messageShown).isLessThanOrEqualTo(now) {
                        animationWithDuration(0.15, { view.animator().alphaValue = 0.0; });
                    } else {
                        // no point in running through the rest.
                        break;
                    }
                }
            }

            // handle compose area.
            if this {
                if online {
                    self.bubbleLayer.opacity = 1.0;
                    self.calloutLayer.opacity = 1.0;
                    self.textField.alphaValue = 1.0;
                } else {
                    self.bubbleLayer.opacity = 0.3;
                    self.calloutLayer.opacity = 0.3;
                    self.textField.alphaValue = 0.3;
                }
                self.window!.makeFirstResponder(self.textField);
                self.textField.currentEditor()!.moveToEndOfLine(nil); // TODO: actually, remembering where they were would be better.
            } else {
                self.bubbleLayer.opacity = 0.0;
                self.calloutLayer.opacity = 0.0;
                self.textField.alphaValue = 0.0;
            }
        });
    }

    private func updateComposeHeight() {
        let height = (self.textField.stringValue == "")
                ? 24.0
                : min(self.composeHeight, self.textField.cell!.cellSizeForBounds(self.textField.bounds).height) + (self.bubbleMarginY * 2);
        let composeArea = NSRect(origin: NSPoint(x: calloutSize, y: self.composeHeight - height), size: NSSize(width: self.width, height: height));
        let bubblePath = NSBezierPath(roundedRect: composeArea, xRadius: bubbleRadius, yRadius: bubbleRadius);
        self.bubbleLayer.path = bubblePath.CGPath;
    }

    required init(coder: NSCoder) {
        fatalError("fauxcoder");
    }
}
