
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

    internal let message: Message;
    internal let conversation: Conversation;

    init(frame: NSRect, width: CGFloat, message: Message, conversation: Conversation) {
        self.textView = NSTextView(frame: NSRect(origin: NSPoint.zero, size: NSSize(width: textWidth, height: 0)));
        self.bubbleLayer = CAShapeLayer();
        self.calloutLayer = CAShapeLayer();
        self.width = width;
        self.message = message;
        self.conversation = conversation;

        super.init(frame: frame);
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        super.viewWillMoveToSuperview(newSuperview);
        self.wantsLayer = true;

        let foreign = self.message.from == self.conversation.with;

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

        // calculate text/bubble frame.
        let size = self.textView.layoutManager!.usedRectForTextContainer(self.textView.textContainer!).size;
        let origin = NSPoint(x: foreign ? (self.width - bubbleMarginX - size.width) : (calloutSize + bubbleMarginX), y: bubbleMarginY);
        self.textView.setFrameOrigin(origin);

        // draw bubble.
        let bubbleRect = NSRect(origin: origin, size: size).insetBy(dx: -bubbleMarginX, dy: -bubbleMarginY);
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: bubbleRadius, yRadius: bubbleRadius);
        self.bubbleLayer.path = bubblePath.CGPath;
        self.bubbleLayer.fillColor = self.bubbleColor;

        // draw callout.
        if foreign {
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
            self.layer!.addSublayer(self.calloutLayer!);
        }

        // add everything.
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
        if self.calloutLayer != nil { self.calloutLayer!.removeFromSuperlayer() };
        self.calloutLayer = nil;
    }
    
    required init(coder: NSCoder) {
        fatalError("vocoder");
    }
}
