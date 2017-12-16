
import Foundation

class IconView: NSView {
    let iconLayer: CALayer;

    init(layer: IconLayer, frame: NSRect) {
        self.iconLayer = layer;

        super.init(frame: frame);
        self.wantsLayer = true;
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        self.iconLayer.frame = NSRect(origin: NSPoint.zero, size: self.frame.size);
        self.layer!.addSublayer(self.iconLayer);
        self.iconLayer.setNeedsDisplay();

        super.viewWillMove(toSuperview: newSuperview);
    }

    required init(coder: NSCoder) { fatalError("iconder"); }
}

class IconLayer: CALayer {
    var _image: NSImage?;
    var image: NSImage? {
        get { return self._image; }
        set {
            self._image = newValue;
            DispatchQueue.main.async(execute: { self.setNeedsDisplay(); });
        }
    }

    override func draw(in ctx: CGContext) {
        self.contentsScale = NSScreen.main!.backingScaleFactor;
        let iconBounds = CGRect(origin: CGPoint.zero, size: self.frame.size);

        if let img = self.image {
            XUIGraphicsPushContext(ctx);
            img.draw(
                in: iconBounds,
                from: CGRect.init(origin: CGPoint.zero, size: img.size),
                operation: .copy,
                fraction: 1.0);
            XUIGraphicsPopContext();
        }
    }
}

class RoundIconLayer: IconLayer {
    override func draw(in ctx: CGContext) {
        self.contentsScale = NSScreen.main!.backingScaleFactor;

        // prepare avatar
        let iconBounds = CGRect(origin: CGPoint.zero, size: self.frame.size);

        // prepare and clip
        XUIGraphicsPushContext(ctx);
        let nsPath = NSBezierPath();
        nsPath.appendRoundedRect(iconBounds,
                                 xRadius: self.frame.size.width / 2,
                                 yRadius: self.frame.size.height / 2);
        nsPath.addClip();

        // draw image
        if let img = self.image {
            img.draw(
                in: iconBounds,
                from: CGRect.init(origin: CGPoint.zero, size: img.size),
                operation: .sourceOver,
                fraction: 0.98);
        }
        
        XUIGraphicsPopContext();
    }
}
