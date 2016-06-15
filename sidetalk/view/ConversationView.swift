
import Foundation

class MessageView: NSView {
    private let textView: NSTextView;
    private let bubbleLayer: CAShapeLayer;
    private var calloutLayer: CAShapeLayer?;

    private let width: CGFloat;

    private let bubbleColor = NSColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 0.5).CGColor;
    private let bubbleMarginX = CGFloat(4);
    private let bubbleMarginY = CGFloat(4);
    private let bubbleRadius = CGFloat(3);

    private let calloutSize = CGFloat(4);

    private let message: Message;

    init(frame: NSRect, width: CGFloat, message: Message) {
        self.textView = NSTextView(frame: NSRect(origin: NSPoint.zero, size: NSSize(width: width, height: 0)));
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
        let verticalCenter = origin.y + size.height / 2;
        let calloutPts = NSPointArray.alloc(3);
        calloutPts[0] = NSPoint(x: rightEdge, y: verticalCenter + calloutSize);
        calloutPts[1] = NSPoint(x: rightEdge + calloutSize, y: verticalCenter);
        calloutPts[2] = NSPoint(x: rightEdge, y: verticalCenter - calloutSize);
        let calloutPath = NSBezierPath();
        calloutPath.appendBezierPathWithPoints(calloutPts, count: 3);
        self.calloutLayer!.path = calloutPath.CGPath;
        self.calloutLayer!.fillColor = self.bubbleColor;

        // add everything.
        self.layer!.addSublayer(self.calloutLayer!);
        self.layer!.addSublayer(self.bubbleLayer);
        self.addSubview(self.textView);

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

class ConversationView: NSView {
    private let conversation: Conversation;
    private let width: CGFloat;

    private var _messages = [MessageView]();

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
    }

    private func drawMessage(message: Message) -> MessageView {
        let view = MessageView(frame: NSRect(origin: NSPoint.zero, size: self.frame.size), width: self.width, message: message);
        dispatch_async(dispatch_get_main_queue(), { self.addSubview(view); });
        return view;
    }

    required init(coder: NSCoder) {
        fatalError("fauxcoder");
    }
}
