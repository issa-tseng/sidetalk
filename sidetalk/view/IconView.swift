
import Foundation

class IconView: NSView {
    let iconLayer: CALayer;

    init(layer: IconLayer, frame: NSRect) {
        self.iconLayer = layer;

        super.init(frame: frame);
        self.wantsLayer = true;
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.iconLayer.frame = NSRect(origin: NSPoint.zero, size: self.frame.size);
        self.layer!.addSublayer(self.iconLayer);
        self.iconLayer.setNeedsDisplay();

        super.viewWillMoveToSuperview(newSuperview);
    }

    required init(coder: NSCoder) { fatalError("iconder"); }
}

class IconLayer: CALayer {
    var _image: NSImage?;
    var image: NSImage? {
        get { return self._image; }
        set {
            self._image = newValue;
            dispatch_async(dispatch_get_main_queue(), { self.setNeedsDisplay(); });
        }
    }

    override func drawInContext(ctx: CGContext) {
        self.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;
        let iconBounds = CGRect(origin: CGPoint.zero, size: self.frame.size);

        if let img = self.image {
            img.drawInRect(
                iconBounds,
                fromRect: CGRect.init(origin: CGPoint.zero, size: img.size),
                operation: .CompositeSourceOver,
                fraction: 1.0);
        }
    }
}

class RoundIconLayer: IconLayer {
    override func drawInContext(ctx: CGContext) {
        self.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;

        // prepare avatar
        let iconBounds = CGRect(origin: CGPoint.zero, size: self.frame.size);

        // prepare and clip
        XUIGraphicsPushContext(ctx);
        let nsPath = NSBezierPath();
        nsPath.appendBezierPathWithRoundedRect(iconBounds,
                                               xRadius: self.frame.size.width / 2,
                                               yRadius: self.frame.size.height / 2);
        nsPath.addClip();

        // draw image
        if let img = self.image {
            img.drawInRect(
                iconBounds,
                fromRect: CGRect.init(origin: CGPoint.zero, size: img.size),
                operation: .CompositeSourceOver,
                fraction: 0.98);
        }
        
        XUIGraphicsPopContext();
    }
}
