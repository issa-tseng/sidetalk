
import Foundation
import ReactiveCocoa
import enum Result.NoError

class MessageView: NSVisualEffectView {
    private let textView: NSTextView;

    private let textWidth = CGFloat(250);
    private let width: CGFloat;

    private var _outerHeight: CGFloat?;
    var outerHeight: CGFloat { get { return self._outerHeight ?? 0; } };

    private let bubbleColor = NSColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 0.35).CGColor;
    private let bubbleMarginX = CGFloat(4);
    private let bubbleMarginY = CGFloat(4);
    private let bubbleRadius = CGFloat(3);

    private let calloutSize = CGFloat(4);

    internal let message: Message;
    internal let conversation: Conversation;

    init(frame: NSRect, width: CGFloat, message: Message, conversation: Conversation) {
        self.textView = NSTextView(frame: NSRect(origin: NSPoint.zero, size: NSSize(width: textWidth, height: 0)));
        self.width = width;
        self.message = message;
        self.conversation = conversation;

        super.init(frame: frame);

        self.material = .Dark;
        self.state = .Active;
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        super.viewWillMoveToSuperview(newSuperview);
        self.wantsLayer = true;

        // render text view.
        self.textView.verticallyResizable = true;
        self.textView.string = self.message.body;
        self.textView.drawsBackground = false;
        self.textView.textColor = NSColor.whiteColor();
        self.textView.font = NSFont.systemFontOfSize(12);

        // autolink and such.
        self.textView.automaticLinkDetectionEnabled = true;
        self.textView.linkTextAttributes?[NSForegroundColorAttributeName] = NSColor.whiteColor();
        self.textView.editable = true;
        self.textView.checkTextInDocument(nil);
        //self.textView.editable = false;
        self.textView.selectable = true;

        // size it up to fit the text.
        self.textView.sizeToFit();

        // clip ourselves.
        self.clip(callout: true);

        // add everything.
        self.addSubview(self.textView);
    }

    // http://stackoverflow.com/a/29386935
    @objc dynamic var cornerMask: NSImage?;
    @objc dynamic func _cornerMask() -> NSImage? { return self.cornerMask; };

    func removeCallout() {
        self.clip(callout: false);
    }

    private func clip(callout callout: Bool) {
        let foreign = self.message.from == self.conversation.with;

        // calculate text/bubble frame.
        let size = self.textView.layoutManager!.usedRectForTextContainer(self.textView.textContainer!).size;
        let origin = NSPoint(x: foreign ? (self.width - bubbleMarginX - size.width) : (calloutSize + bubbleMarginX), y: bubbleMarginY);

        // draw bubble.
        let bubbleRect = NSRect(origin: origin, size: size).insetBy(dx: -bubbleMarginX, dy: -bubbleMarginY);
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: bubbleRadius, yRadius: bubbleRadius);

        // HACK: bad place for these lines.
        self.textView.setFrameOrigin(origin);
        self._outerHeight = bubbleRect.height;

        // create clipping mask.
        let clip = NSImage(size: self.frame.size, flipped: false) { rect in
            NSColor.blackColor().set();
            bubblePath.fill();

            // draw callout.
            if foreign && callout {
                let rightEdge = origin.x + size.width + self.bubbleMarginX;
                let vlineCenter = origin.y + 7.0;
                let calloutPts = NSPointArray.alloc(3);
                calloutPts[0] = NSPoint(x: rightEdge, y: vlineCenter + self.calloutSize);
                calloutPts[1] = NSPoint(x: rightEdge + self.calloutSize, y: vlineCenter);
                calloutPts[2] = NSPoint(x: rightEdge, y: vlineCenter - self.calloutSize);
                let calloutPath = NSBezierPath();
                calloutPath.appendBezierPathWithPoints(calloutPts, count: 3);
                calloutPath.fill();
            }

            return true;
        };
        clip.capInsets = NSEdgeInsets(top: bubbleRadius, left: bubbleRadius, bottom: bubbleRadius, right: bubbleRadius);
        clip.resizingMode = .Tile;
        self.maskImage = clip;
    }

    required init(coder: NSCoder) {
        fatalError("vocoder");
    }
}
