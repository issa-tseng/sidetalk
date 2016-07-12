
import Foundation

enum CalloutSide { case Left, Right; }
class BubbleView: NSVisualEffectView {
    private var _calloutSide: CalloutSide = .Left;
    var calloutSide: CalloutSide {
        get { return self._calloutSide; }
        set {
            self._calloutSide = newValue;
            self.clip();
        }
    }

    private var _calloutShown: Bool = true;
    var calloutShown: Bool {
        get { return self._calloutShown; }
        set {
            self._calloutShown = newValue;
            self.clip();
        }
    }

    override func viewWillMoveToSuperview(view: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(view);
        if self.material == .AppearanceBased { self.material = .Dark; }
        self.state = .Active;
    }

    override func setFrameSize(newSize: NSSize) {
        super.setFrameSize(newSize);
        self.clip();
    }

    // http://stackoverflow.com/a/29386935
    private func clip() {
        // create clipping mask.
        let clip = NSImage(size: self.frame.size, flipped: false) { rect in
            NSColor.blackColor().set();

            // draw bubble.
            let origin = NSPoint(x: (self.calloutSide == .Left) ? ST.message.calloutSize : 0, y: 0);
            let size = NSSize(width: self.frame.size.width - ST.message.calloutSize, height: self.frame.size.height);
            NSBezierPath(roundedRect: NSRect(origin: origin, size: size), cornerRadius: ST.message.radius).fill();

            // draw callout.
            if self.calloutShown {
                let (edge, sign) = (self.calloutSide == .Left) ? (ST.message.calloutSize, CGFloat(-1)) : (self.frame.width - ST.message.calloutSize, CGFloat(1));

                let calloutPts = NSPointArray.alloc(3);
                calloutPts[0] = NSPoint(x: edge, y: ST.message.calloutVline + ST.message.calloutSize);
                calloutPts[1] = NSPoint(x: edge + (ST.message.calloutSize * sign), y: ST.message.calloutVline);
                calloutPts[2] = NSPoint(x: edge, y: ST.message.calloutVline - ST.message.calloutSize);

                let calloutPath = NSBezierPath();
                calloutPath.appendBezierPathWithPoints(calloutPts, count: 3);
                calloutPath.fill();
            }

            return true;
        };
        clip.resizingMode = .Tile;
        self.maskImage = clip;
    }
}
