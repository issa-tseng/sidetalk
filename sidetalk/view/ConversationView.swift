
import Foundation
import ReactiveCocoa
import enum Result.NoError

struct MessageViews {
    let container: NSTextContainer;
    let textView: NSTextView;
    let bubble: BubbleView;
    let message: Message;
};

enum DisplayMode { case Normal, Compact; };

class ConversationView: NSView {
    internal let conversation: Conversation;
    private let width: CGFloat;

    private let _mainView: MainView;

    // compose area objects.
    private let composeBubble = BubbleView();
    private let textField: NSTextField;

    // message area objects.
    private let scrollView = NSScrollView();
    private let scrollContents = NSView();
    private var bottomConstraint: NSLayoutConstraint?;

    private let titleText = NSTextView();
    private let titleBubble = BubbleView();

    private let truncateText = NSTextField();
    private let truncateBubble = BubbleView();
    private var truncateMessage: NSTextView?;

    private let textLayout = NSLayoutManager();
    private let textStorage = NSTextStorage();
    private let textMeasurer = NSTextView();
    private var messageViews = [MessageViews]();

    // signals and such.
    private var _initiallyActivated = false;
    private let _active = MutableProperty<Bool>(false);
    var active: Signal<Bool, NoError> { get { return self._active.signal; } };
    var active_: Bool { get { return self._active.value; } };

    private let _lastShown = MutableProperty<NSDate>(NSDate.distantPast());
    var lastShown: Signal<NSDate, NoError> { get { return self._lastShown.signal; } };
    var lastShown_: NSDate { get { return self._lastShown.value; } };

    private let _displayMode = MutableProperty<DisplayMode>(.Normal);
    var displayMode: Signal<DisplayMode, NoError> { get { return self._displayMode.signal; } };
    var displayMode_: DisplayMode {
        get { return self._displayMode.value; }
        set { self._displayMode.modify({ _ in newValue }) }
    };

    private let _searchLeecher: STTextDelegate;
    var text: Signal<String, NoError> { get { return self._searchLeecher.text; } };

    init(frame: NSRect, width: CGFloat, conversation: Conversation, mainView: MainView) {
        self.width = width;
        self.conversation = conversation;
        self._mainView = mainView;

        self.textField = NSTextField(frame: NSRect(origin: NSPoint(x: ST.message.calloutSize, y: 0), size: NSSize(width: self.width, height: ST.conversation.composeHeight)).insetBy(dx: ST.message.paddingX, dy: ST.message.paddingY));
        self._searchLeecher = STTextDelegate(field: self.textField);

        super.init(frame: frame);
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(newSuperview);

        self.autoresizesSubviews = false;
        self.prepare();

        // draw bubble.
        self.updateComposeHeight();
        self.composeBubble.color = .Compose;

        // set up textfield.
        self.textField.backgroundColor = NSColor.clearColor();
        self.textField.bezeled = false;
        self.textField.focusRingType = NSFocusRingType.None;
        self.textField.font = NSFont.systemFontOfSize(ST.conversation.composeTextSize);
        self.textField.lineBreakMode = .ByWordWrapping;
        self.textField.alphaValue = 0.0;

        // add layers.
        self.addSubview(self.composeBubble);
        self.addSubview(self.textField);

        // init message text storage.
        self.textStorage.addLayoutManager(self.textLayout);

        // set up the scroll view itself.
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false;
        self.scrollView.hasVerticalScroller = true;
        self.scrollView.scrollerStyle = .Overlay;
        self.scrollView.drawsBackground = false;
        self.addSubview(self.scrollView);

        self.addConstraints([
            self.scrollView.constrain.width == self.width, self.scrollView.constrain.top == self.constrain.top,
            self.scrollView.constrain.bottom == self.constrain.bottom - (ST.conversation.composeHeight + ST.conversation.composeMargin)
        ]);

        // set up the scroll contents container.
        self.scrollView.documentView = self.scrollContents;
        self.scrollContents.frame = self.scrollView.contentView.bounds;
        self.scrollContents.translatesAutoresizingMaskIntoConstraints = false;
        let views = [ "scrollContents": self.scrollContents ];
        self.scrollView.contentView.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|[scrollContents]|",
            options: NSLayoutFormatOptions(), metrics: nil, views: views));
        self.scrollView.contentView.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:[scrollContents]|",
            options: NSLayoutFormatOptions(), metrics: nil, views: views));

        // set up the bubble underlying the title.
        self.titleBubble.color = .Title;
        self.titleBubble.calloutShown = false;
        self.titleBubble.alphaValue = 0.6;
        self.titleBubble.translatesAutoresizingMaskIntoConstraints = false;
        self.scrollContents.addSubview(self.titleBubble);

        // set up the title inside the scroll area.
        let title = NSAttributedString(string: "Conversation with \(self.conversation.with.displayName)", attributes: ST.conversation.titleTextAttr);
        self.titleText.drawsBackground = false;
        self.titleText.selectable = false;
        self.titleText.textStorage!.setAttributedString(title);
        self.titleText.translatesAutoresizingMaskIntoConstraints = false;
        self.titleText.alphaValue = 0;
        self.scrollContents.addSubview(self.titleText);

        // layout both title objects.
        self.scrollContents.addConstraints([
            self.scrollContents.constrain.top == self.titleText.constrain.top - ST.message.paddingY,
            self.scrollContents.constrain.left == self.titleText.constrain.left - ST.message.paddingX,
            self.scrollContents.constrain.right == self.titleText.constrain.right + ST.message.paddingX,
            self.titleText.constrain.height == ST.conversation.titleTextHeight
        ]);
        self.bottomConstraint = (self.scrollContents.constrain.bottom == self.titleText.constrain.bottom + ST.message.paddingY);
        self.scrollContents.addConstraint(self.bottomConstraint!);
        self.scrollContents.addConstraints([
            self.titleBubble.constrain.top == self.titleText.constrain.top - ST.message.paddingY,
            self.titleBubble.constrain.right == self.titleText.constrain.right + ST.message.paddingX,
            self.titleBubble.constrain.bottom == self.titleText.constrain.bottom + ST.message.paddingY,
            self.titleBubble.constrain.left == self.titleText.constrain.left - ST.message.paddingX
        ]);

        // set up the truncated text+bubble for overlong notifications.
        let truncateBounds = NSRect(origin: NSPoint(x: 0, y: ST.conversation.composeHeight + ST.conversation.composeMargin), size: NSSize(width: self.width, height: 25));
        self.truncateBubble.calloutShown = true;
        self.truncateBubble.calloutSide = .Right;
        self.truncateBubble.color = .Foreign;
        self.truncateBubble.frame = truncateBounds;
        self.truncateText.editable = false;
        self.truncateText.usesSingleLineMode = true;
        self.truncateText.lineBreakMode = .ByTruncatingTail;
        self.truncateText.backgroundColor = NSColor.clearColor();
        self.truncateText.font = NSFont.systemFontOfSize(12);
        self.truncateText.drawsBackground = false;
        self.truncateText.bezeled = false;
        self.truncateText.textColor = NSColor.whiteColor();
        self.truncateText.frame = NSRect(origin: truncateBounds.insetBy(dx: ST.message.paddingX, dy: ST.message.paddingY).origin,
                                         size: NSSize(width: self.width - (2 * ST.message.paddingX) - ST.message.calloutSize, height: 16));
        self.truncateBubble.alphaValue = 0;
        self.truncateText.alphaValue = 0;
        self.addSubview(self.truncateBubble);
        self.addSubview(self.truncateText);

        // set up an invisible field we'll use to measure message sizes.
        self.textMeasurer.frame = NSRect(origin: NSPoint.zero, size: NSSize(width: 250, height: 0));
        self.textMeasurer.verticallyResizable = true;
        self.textMeasurer.font = NSFont.systemFontOfSize(12);
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
        let delayedMessage = allMessages.delay(ST.message.shownFor, onScheduler: scheduler);

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

                if !active || self.lastShown_.dateByAddingTimeInterval(ST.conversation.sendLockout).isGreaterThan(NSDate()) { return; }

                if self.conversation.connection.hasInternet_ && (key == .Return) && (self.textField.stringValue != "") {
                    self.conversation.sendMessage(self.textField.stringValue);
                    self.textField.stringValue = "";
                } else if key == .LineBreak {
                    self.textField.insertText("\n");
                }
            };

        self._active.modify({ _ in self._initiallyActivated });

        self.text.observeNext { _ in self.updateComposeHeight(); };

        let immediateChatState = self.text.map { (text) -> ChatState in (text == "") ? .Active : .Composing };
        let delayedChatState = self.text.debounce(NSTimeInterval(5), onScheduler: scheduler).map { (text) -> ChatState in (text == "") ? .Active : .Paused };
        immediateChatState.merge(delayedChatState).skipRepeats().observeNext { state in self.conversation.sendChatState(state); };
    }

    private func drawMessage(message: Message) {
        dispatch_async(dispatch_get_main_queue(), {
            let foreign = message.isForeign();

            // update our total stored text, with link detection.
            let mutable = NSMutableAttributedString(string: message.body);
            let fullRange = NSRange(location: 0, length: message.body.characters.count);
            mutable.addAttributes(ST.message.textAttr, range: fullRange);
            let detector = try! NSDataDetector(types: NSTextCheckingType.Link.rawValue);
            detector.enumerateMatchesInString(message.body, options: NSMatchingOptions(), range: fullRange, usingBlock: { match, _, _ in
                if let url = match?.URL { mutable.addAttributes([ NSLinkAttributeName: url ], range: match!.range); }
            });
            let nonmutable = mutable.copy() as! NSAttributedString;
            self.textStorage.appendAttributedString(nonmutable);
            self.textStorage.appendAttributedString(NSAttributedString(string: "\n"));

            // create a new text container that tracks the view.
            let textContainer = NSTextContainer();
            textContainer.widthTracksTextView = true;
            textContainer.heightTracksTextView = true;

            // measure the new message so we know how big to make the textView.
            self.textMeasurer.textStorage!.setAttributedString(mutable);
            self.textMeasurer.sizeToFit();
            let measuredSize = self.textMeasurer.layoutManager!.usedRectForTextContainer(self.textMeasurer.textContainer!).size;
            let size = NSSize(width: measuredSize.width + 1.0, height: measuredSize.height); // HACK: why is this 1 pixel off?

            // create the textView, set basic attributes.
            let textView = NSTextView(frame: NSRect(origin: NSPoint.zero, size: size), textContainer: textContainer);
            textView.translatesAutoresizingMaskIntoConstraints = false;
            textView.linkTextAttributes?[NSForegroundColorAttributeName] = NSColor.whiteColor();
            textView.drawsBackground = false;
            textView.editable = false;
            textView.selectable = true;

            // set tooltip to the receipt timestamp.
            let formatter = NSDateFormatter();
            formatter.timeStyle = .MediumStyle;
            formatter.dateStyle = .ShortStyle;
            formatter.doesRelativeDateFormatting = true;
            textView.toolTip = formatter.stringFromDate(message.at);

            // make a bubble.
            let bubbleView = BubbleView();
            bubbleView.translatesAutoresizingMaskIntoConstraints = false;
            bubbleView.calloutSide = foreign ? .Right : .Left;
            bubbleView.calloutShown = foreign ? true : false;
            bubbleView.color = foreign ? .Foreign : .Own;

            // save off the objects.
            self.messageViews.insert(MessageViews(container: textContainer, textView: textView, bubble: bubbleView, message: message), atIndex: 0);

            // add our views.
            self.scrollContents.addSubview(bubbleView);
            self.scrollContents.addSubview(textView);
            self.textLayout.addTextContainer(textContainer);

            ///////////////////////////
            // set up our constraints:
            // size the message.
            self.scrollContents.addConstraint(textView.constrain.width == size.width);
            self.scrollContents.addConstraint(textView.constrain.height == size.height);

            // put the message in the correct horizontal position.
            let hAttribute: NSLayoutAttribute = foreign ? .Right : .Left;
            let hOffset = (foreign ? -1 : 1) * (ST.message.paddingX + ST.message.calloutSize);
            self.scrollContents.addConstraint(textView.constrain.my(hAttribute) == self.scrollContents.constrain.my(hAttribute) + hOffset);

            // clear out the old bottom-lock.
            if let constraint = self.bottomConstraint { self.scrollContents.removeConstraint(constraint); }

            if self.messageViews.count == 1 {
                // lock the bottom of the title text to the first message.
                self.scrollContents.addConstraint(self.titleText.constrain.bottom == textView.constrain.top - (3 * ST.message.paddingY));
            } else if self.messageViews.count > 1 {
                // space vertically the new message with the old.
                let vdist = ST.message.margin + ST.message.paddingY * 2;
                self.scrollContents.addConstraint(self.messageViews[1].textView.constrain.bottom == textView.constrain.top - vdist);

                // while we're here, clear out that bubble.
                self.messageViews[1].bubble.calloutShown = false;
            }

            // lock the newest message to the bottom.
            self.bottomConstraint = (textView.constrain.bottom == self.scrollContents.constrain.bottom - (ST.message.paddingY + ST.message.margin));
            self.scrollContents.addConstraint(self.bottomConstraint!);

            // position the bubble.
            self.scrollContents.addConstraints([
                bubbleView.constrain.top == textView.constrain.top - ST.message.paddingY - (ST.message.outlineWidth / 2),
                bubbleView.constrain.bottom == textView.constrain.bottom + ST.message.paddingY + (ST.message.outlineWidth / 2),
                bubbleView.constrain.left == textView.constrain.left - (ST.message.paddingX + (foreign ? 0 : ST.message.calloutSize + ST.message.outlineWidth)) - (ST.message.outlineWidth / 2),
                bubbleView.constrain.right == textView.constrain.right + (ST.message.paddingX + (foreign ? ST.message.calloutSize + ST.message.outlineWidth : 0)) + (ST.message.outlineWidth / 2)
            ]);

            // hide the fallback bubble.
            self.truncateText.alphaValue = 0;
            self.truncateBubble.alphaValue = 0;

            // if we're inactive and in compact mode, clear out the previous bubble.
            if !self.active_ && self.displayMode_ == .Compact && self.messageViews.count > 1 {
                self.messageViews[1].textView.alphaValue = 0;
                self.messageViews[1].bubble.alphaValue = 0;

                // and if we're too tall, show the fallback bubble instead.
                if size.height > ST.message.multilineCutoff {
                    textView.alphaValue = 0;
                    bubbleView.alphaValue = 0;

                    self.truncateText.stringValue = message.body;
                    self.truncateText.animator().alphaValue = 1;
                    self.truncateBubble.animator().alphaValue = 1;
                    self.truncateMessage = textView;
                }
            }
        });
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

    // ignore mouse events if we are not active.
    override func hitTest(point: NSPoint) -> NSView? {
        if self._active.value { return super.hitTest(point); }
        else { return nil; }
    }

    // kind of a misnomer; this doesn't lay anything out at all. it just controls visibility.
    private func relayout(lastState: (Bool, Bool), _ thisState: (Bool, Bool)) {
        let (last, _) = lastState;
        let (this, online) = thisState;

        dispatch_async(dispatch_get_main_queue(), {
            // handle messages.
            if !last && this {
                // show all messages. TODO: don't bother to animate offscreen stuff.
                for (idx, messagePack) in self.messageViews.enumerate() {
                    animationWithDuration(0.1 + (0.07 * Double(idx)), {
                        messagePack.textView.animator().alphaValue = 1.0;
                        messagePack.bubble.animator().alphaValue = 1.0;
                    });
                }
            } else if last && !this {
                // hide all messages.
                for (idx, messagePack) in self.messageViews.enumerate() {
                    animationWithDuration(0.2 + (0.04 * Double(idx)), {
                        messagePack.textView.animator().alphaValue = 0.0;
                        messagePack.bubble.animator().alphaValue = 0.0;
                    });
                }
            } else if !this {
                // hide individual messages that may have been shown on receipt.
                let now = NSDate();
                for messagePack in self.messageViews {
                    if messagePack.message.at.dateByAddingTimeInterval(ST.message.shownFor).isLessThanOrEqualTo(now) {
                        if messagePack.textView == self.truncateMessage {
                            animationWithDuration(0.15, {
                                self.truncateText.animator().alphaValue = 0.0;
                                self.truncateBubble.animator().alphaValue = 0.0;
                            });
                        } else {
                            animationWithDuration(0.15, {
                                messagePack.textView.animator().alphaValue = 0.0;
                                messagePack.bubble.animator().alphaValue = 0.0;
                            });
                        }
                    } else {
                        // no point in running through the rest.
                        break;
                    }
                }
            }

            // handle other elements.
            if this {
                self.titleText.alphaValue = 1.0;
                self.titleBubble.alphaValue = 0.6;
                if online {
                    self.textField.alphaValue = 1.0;
                    self.composeBubble.alphaValue = 1.0;
                } else {
                    self.textField.alphaValue = 0.3;
                    self.composeBubble.alphaValue = 0.4;
                }
                self.truncateText.alphaValue = 0;
                self.truncateBubble.alphaValue = 0;
                self.window!.makeFirstResponder(self.textField);
                self.textField.currentEditor()!.moveToEndOfLine(nil); // TODO: actually, remembering where they were would be better.
            } else {
                self.titleText.alphaValue = 0.0;
                self.titleBubble.alphaValue = 0.0;
                self.textField.alphaValue = 0.0;
                self.composeBubble.alphaValue = 0.0;
            }
        });
    }

    private var lastHeight = CGFloat(0);
    private func updateComposeHeight() {
        let height = (self.textField.stringValue == "") ? 24.0 : min(ST.conversation.composeHeight,
                                                                     self.textField.cell!.cellSizeForBounds(self.textField.bounds).height) + (ST.message.paddingY * 2);
        if height == lastHeight { return; }
        lastHeight = height;

        self.composeBubble.frame = NSRect(origin: NSPoint(x: 0, y: ST.conversation.composeHeight - height),
                                          size: NSSize(width: self.width, height: height));
    }

    required init(coder: NSCoder) {
        fatalError("fauxcoder");
    }
}
