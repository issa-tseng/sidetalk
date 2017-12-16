
import Foundation;
import ReactiveSwift;
import enum Result.NoError;

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

    private let _lastShown = MutableProperty<Date>(Date.distantPast);
    var lastShown: Signal<Date, NoError> { get { return self._lastShown.signal; } };
    var lastShown_: Date { get { return self._lastShown.value; } };

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

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMove(toSuperview: newSuperview);

        self.autoresizesSubviews = false;
        self.prepare();

        // draw bubble.
        self.updateComposeHeight();
        self.composeBubble.color = .Compose;

        // set up textfield.
        self.textField.backgroundColor = NSColor.clear;
        self.textField.isBezeled = false;
        self.textField.focusRingType = NSFocusRingType.none;
        self.textField.font = NSFont.systemFont(ofSize: ST.conversation.composeTextSize);
        self.textField.lineBreakMode = .byWordWrapping;
        self.textField.alphaValue = 0.0;

        // add layers.
        self.addSubview(self.composeBubble);
        self.addSubview(self.textField);

        // init message text storage.
        self.textStorage.addLayoutManager(self.textLayout);

        // set up the truncated text+bubble for overlong notifications.
        let truncateBounds = NSRect(origin: NSPoint(x: 0, y: ST.conversation.composeHeight + ST.conversation.composeMargin), size: NSSize(width: self.width, height: 25));
        self.truncateBubble.calloutShown = true;
        self.truncateBubble.calloutSide = .Right;
        self.truncateBubble.color = .Foreign;
        self.truncateBubble.frame = truncateBounds;
        self.truncateText.isEditable = false;
        self.truncateText.usesSingleLineMode = true;
        self.truncateText.lineBreakMode = .byTruncatingTail;
        self.truncateText.backgroundColor = NSColor.clear;
        self.truncateText.font = NSFont.systemFont(ofSize: 12);
        self.truncateText.drawsBackground = false;
        self.truncateText.isBezeled = false;
        self.truncateText.textColor = NSColor.white;
        self.truncateText.frame = NSRect(origin: truncateBounds.insetBy(dx: ST.message.paddingX, dy: ST.message.paddingY).origin,
                                         size: NSSize(width: self.width - (2 * ST.message.paddingX) - ST.message.calloutSize, height: 16));
        self.truncateBubble.alphaValue = 0;
        self.truncateText.alphaValue = 0;
        self.addSubview(self.truncateBubble);
        self.addSubview(self.truncateText);

        // set up the scroll view itself.
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false;
        self.scrollView.hasVerticalScroller = true;
        self.scrollView.scrollerStyle = .overlay;
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
        self.scrollView.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[scrollContents]|",
            options: NSLayoutConstraint.FormatOptions(), metrics: nil, views: views));
        self.scrollView.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[scrollContents]|",
            options: NSLayoutConstraint.FormatOptions(), metrics: nil, views: views));

        // set up the bubble underlying the title.
        self.titleBubble.color = .Title;
        self.titleBubble.calloutShown = false;
        self.titleBubble.alphaValue = 0.6;
        self.titleBubble.translatesAutoresizingMaskIntoConstraints = false;
        self.scrollContents.addSubview(self.titleBubble);

        // set up the title inside the scroll area.
        let title = NSAttributedString(string: "Conversation with \(self.conversation.with.displayName)", attributes: ST.conversation.titleTextAttr);
        self.titleText.drawsBackground = false;
        self.titleText.isSelectable = false;
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

        // set up an invisible field we'll use to measure message sizes.
        self.textMeasurer.frame = NSRect(origin: NSPoint.zero, size: NSSize(width: 250, height: 0));
        self.textMeasurer.isVerticallyResizable = true;
        self.textMeasurer.font = NSFont.systemFont(ofSize: 12);
        self.textMeasurer.textContainerInset = NSSize.zero;
        self.textMeasurer.textContainer!.lineFragmentPadding = 0;
    }

    // like conversation#latestMessage, but returns all messages we know about.
    func allMessages() -> Signal<Message, NoError> {
        let managed = ManagedSignal<Message>();

        DispatchQueue.global(qos: .userInitiated).async(execute: {
            for message in self.conversation.messages.reversed() { managed.observer.send(value: message); }
            self.conversation.latestMessage.observeValues({ message in managed.observer.send(value: message); });
        });

        return managed.signal;
    }

    private func prepare() {
        let allMessages = self.allMessages();
        allMessages.observeValues { message in self.drawMessage(message) };

        let scheduler = QueueScheduler(qos: .default, name: "delayed-messages-conversationview");
        let delayedMessage = allMessages.delay(ST.message.shownFor, on: scheduler);

        self.active
            .combineWithDefault(delayedMessage.downcastToOptional(), defaultValue: nil).map({ active, _ in active })
            .combineWithDefault(self.conversation.connection.hasInternet, defaultValue: true)
            .combineWithDefault(self.conversation.connection.authenticated, defaultValue: true).map({ ($0.0, $0.1 && $1) }) // doesn't matter which flag is which, combine.
            .combinePrevious((false, true))
            .observeValues({ states in self.relayout(states.0, states.1); });

        // TODO: it's entirely possible that the better way to do this would be to drop Impulses altogether and
        // simply consume the keystroke entirely within MainView. but for now, bodge it with a delay.
        let keyTracker = Impulse.track(Key.self);
        GlobalInteraction.sharedInstance.keyPress
            .combineWithDefault(self.active, defaultValue: false)
            .observeValues { wrappedKey, active in
                let key = keyTracker.extract(wrappedKey);

                if !active || (self.lastShown_.addingTimeInterval(ST.conversation.sendLockout) > Date()) { return; }

                if self.conversation.connection.hasInternet_ && (key == .Return) && (self.textField.stringValue != "") {
                    self.conversation.sendMessage(self.textField.stringValue);
                    self.textField.stringValue = "";
                } else if key == .LineBreak {
                    self.textField.insertText("\n");
                }
            };

        self._active.modify({ _ in self._initiallyActivated });

        self.text.observeValues { _ in self.updateComposeHeight(); };

        let immediateChatState = self.text.map { (text) -> ChatState in (text == "") ? .Active : .Composing };
        let delayedChatState = self.text.debounce(TimeInterval(5), on: scheduler).map { (text) -> ChatState in (text == "") ? .Active : .Paused };
        immediateChatState.merge(delayedChatState).skipRepeats().observeValues { state in self.conversation.sendChatState(state); };
    }

    private func drawMessage(_ message: Message) {
        DispatchQueue.main.async(execute: {
            let foreign = message.isForeign();

            // update our total stored text, with link detection.
            let mutable = NSMutableAttributedString(string: message.body, attributes: ST.message.textAttr);
            let fullRange = NSRange(location: message.body.startIndex.encodedOffset, length: message.body.endIndex.encodedOffset); // TODO: is this actually the full range?
            let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue);
            detector.enumerateMatches(in: message.body, options: NSRegularExpression.MatchingOptions(), range: fullRange, using: { match, _, _ in
                if let url = match?.url { mutable.addAttributes([ NSAttributedStringKey.link: url ], range: match!.range); }
            });
            let nonmutable = mutable.copy() as! NSAttributedString;
            self.textStorage.append(nonmutable);
            self.textStorage.append(NSAttributedString(string: "\n"));

            // create a new text container that tracks the view.
            let textContainer = NSTextContainer();
            textContainer.lineFragmentPadding = 0;
            textContainer.widthTracksTextView = true;
            textContainer.heightTracksTextView = true;

            // measure the new message so we know how big to make the textView.
            self.textMeasurer.textStorage!.setAttributedString(mutable);
            self.textMeasurer.sizeToFit();
            let measuredSize = ceil(self.textMeasurer.layoutManager!.usedRect(for: self.textMeasurer.textContainer!).size);
            let size = NSSize(width: measuredSize.width, height: measuredSize.height);

            // create the textView, set basic attributes.
            let textView = NSTextView(frame: NSRect(origin: NSPoint.zero, size: size), textContainer: textContainer);
            textView.translatesAutoresizingMaskIntoConstraints = false;
            textView.linkTextAttributes?[NSAttributedStringKey.foregroundColor] = NSColor.white;
            textView.drawsBackground = false;
            textView.isEditable = false;
            textView.isSelectable = true;
            textView.textContainerInset = NSSize.zero;

            // set tooltip to the receipt timestamp.
            let formatter = DateFormatter();
            formatter.timeStyle = .medium;
            formatter.dateStyle = .short;
            formatter.doesRelativeDateFormatting = true;
            textView.toolTip = formatter.string(from: message.at);

            // make a bubble.
            let bubbleView = BubbleView();
            bubbleView.translatesAutoresizingMaskIntoConstraints = false;
            bubbleView.calloutSide = foreign ? .Right : .Left;
            bubbleView.calloutShown = foreign ? true : false;
            bubbleView.color = foreign ? .Foreign : .Own;

            // save off the objects.
            self.messageViews.insert(MessageViews(container: textContainer, textView: textView, bubble: bubbleView, message: message), at: 0);

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
            let hAttribute: NSLayoutConstraint.Attribute = foreign ? .right : .left;
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

            // hide off the bat if this message is old.
            if !self.active_ && (message.at.addingTimeInterval(ST.message.shownFor) <= Date()) {
                bubbleView.alphaValue = 0.0;
                textView.alphaValue = 0.0;
            }

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

            // scroll to the bottom if we're inactive. (leave it alone if the user might be scrolling manually)
            if !self.active_ { self.scrollView.contentView.scroll(to: NSPoint.zero); }
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
    override func hitTest(_ point: NSPoint) -> NSView? {
        if self._active.value { return super.hitTest(point); }
        else { return nil; }
    }

    // kind of a misnomer; this doesn't lay anything out at all. it just controls visibility.
    private func relayout(_ lastState: (Bool, Bool), _ thisState: (Bool, Bool)) {
        let (last, _) = lastState;
        let (this, online) = thisState;

        DispatchQueue.main.async(execute: {
            // handle messages.
            if !last && this {
                // show all messages. TODO: don't bother to animate offscreen stuff.
                for (idx, messagePack) in self.messageViews.enumerated() {
                    animationWithDuration(duration: 0.1 + (0.07 * Double(idx)), {
                        messagePack.textView.animator().alphaValue = 1.0;
                        messagePack.bubble.animator().alphaValue = 1.0;
                    });
                }
            } else if last && !this {
                // hide all messages.
                for (idx, messagePack) in self.messageViews.enumerated() {
                    animationWithDuration(duration: 0.2 + (0.04 * Double(idx)), {
                        messagePack.textView.animator().alphaValue = 0.0;
                        messagePack.bubble.animator().alphaValue = 0.0;
                    });
                }
            } else if !this {
                // hide individual messages that may have been shown on receipt.
                let now = Date();
                for messagePack in self.messageViews {
                    if messagePack.message.at.addingTimeInterval(ST.message.shownFor) <= now {
                        if messagePack.textView == self.truncateMessage {
                            animationWithDuration(duration: 0.15, {
                                self.truncateText.animator().alphaValue = 0.0;
                                self.truncateBubble.animator().alphaValue = 0.0;
                            });
                        } else {
                            animationWithDuration(duration: 0.15, {
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
        let height = (self.textField.stringValue == "") ? 26.0 : min(ST.conversation.composeHeight,
            self.textField.cell!.cellSize(forBounds: self.textField.bounds).height) + (ST.message.paddingY * 2);
        if height == lastHeight { return; }
        lastHeight = height;

        self.composeBubble.frame = NSRect(origin: NSPoint(x: 0, y: ST.conversation.composeHeight - height),
                                          size: NSSize(width: self.width, height: height));
    }

    required init(coder: NSCoder) {
        fatalError("fauxcoder");
    }
}
