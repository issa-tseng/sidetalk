
import Foundation

enum CalloutSide { case Left, Right; }
class BubbleView: NSView {
    private let bubbleLayer = CAShapeLayer();
    private let calloutLayer = CAShapeLayer();

    private var _calloutSide: CalloutSide = .Left;
    var calloutSide: CalloutSide {
        get { return self._calloutSide; }
        set { self._calloutSide = newValue; self.relayout(); }
    };

    private var _calloutShown: Bool = true;
    var calloutShown: Bool {
        get { return self._calloutShown; }
        set { self._calloutShown = newValue; self.relayout(); }
    };

    private var _bubbleColor: CGColor?;
    var bubbleColor: CGColor? {
        get { return self._bubbleColor; }
        set {
            self._bubbleColor = newValue;
            self.bubbleLayer.fillColor = newValue;
            self.calloutLayer.fillColor = newValue;
        }
    };

    override func viewWillMoveToSuperview(view: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(view);

        if self.bubbleColor == nil { self.bubbleColor = ST.message.bg };
        self.layer!.addSublayer(self.bubbleLayer);
        self.layer!.addSublayer(self.calloutLayer);
    }

    override func setFrameSize(newSize: NSSize) {
        super.setFrameSize(newSize);
        self.relayout();
    }

    private func relayout() {
        // draw bubble.
        let origin = NSPoint(x: (self.calloutSide == .Left) ? ST.message.calloutSize : 0, y: 0);
        let size = NSSize(width: self.frame.size.width - ST.message.calloutSize, height: self.frame.size.height);
        self.bubbleLayer.path = NSBezierPath(roundedRect: NSRect(origin: origin, size: size), cornerRadius: ST.message.radius).CGPath;

        // draw callout.
        if self.calloutShown {
            let (edge, sign) = (self.calloutSide == .Left) ? (ST.message.calloutSize, CGFloat(-1)) : (self.frame.width - ST.message.calloutSize, CGFloat(1));

            let calloutPts = NSPointArray.alloc(3);
            calloutPts[0] = NSPoint(x: edge, y: ST.message.calloutVline + ST.message.calloutSize);
            calloutPts[1] = NSPoint(x: edge + (ST.message.calloutSize * sign), y: ST.message.calloutVline);
            calloutPts[2] = NSPoint(x: edge, y: ST.message.calloutVline - ST.message.calloutSize);

            let calloutPath = NSBezierPath();
            calloutPath.appendBezierPathWithPoints(calloutPts, count: 3);

            self.calloutLayer.path = calloutPath.CGPath;
            self.calloutLayer.hidden = false;
        } else {
            self.calloutLayer.hidden = true;
        }
    }
}
