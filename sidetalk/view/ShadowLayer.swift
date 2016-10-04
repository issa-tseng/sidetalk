
import Foundation

class ShadowLayer: CALayer {
    private var _width: CGFloat = 0;
    var width: CGFloat {
        get { return self._width; }
        set {
            self._width = newValue;
            dispatch_async(dispatch_get_main_queue(), { self.setNeedsDisplay(); });
        }
    }
    private var _radius: CGFloat = 3;
    var radius: CGFloat {
        get { return self._radius; }
        set {
            self._radius = newValue;
            dispatch_async(dispatch_get_main_queue(), { self.setNeedsDisplay(); });
        }
    }

    override func drawInContext(ctx: CGContext) {
        // retina?
        self.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;

        // don't bother drawing anything if we have no width.
        if self._width <= 0 { return; }

        // generate the initial box image.
        let width = min(self._width + self._radius + (3 * self._radius * (self._width / (self.frame.width - (2 * self._radius)))), self.frame.width - (2 * self._radius));
        let bounds = CGRect(origin: CGPoint(x: self.frame.width - self._radius - width, y: self._radius),
                            size: CGSize(width: width, height: self.frame.height - (2 * self._radius)));
        let path = NSBezierPath(roundedRect: bounds, cornerRadius: self._radius);

        let box = NSImage(size: self.frame.size, flipped: false) { rect in
            NSColor.blackColor().set();
            path.fill();
            return true;
        };

        // create the blur filter.
        let blurFilter = CIFilter(name: "CIGaussianBlur")!;
        blurFilter.setDefaults();
        blurFilter.setValue(self._radius, forKey: "inputRadius");

        // feed the image into the filter.
        let cgImage = box.CGImageForProposedRect(nil, context: NSGraphicsContext.currentContext(), hints: nil)!;
        let ciImage = CIImage(CGImage: cgImage);
        blurFilter.setValue(ciImage, forKey: "inputImage");

        // now get it back out of the filter. :/
        let rep = NSCIImageRep(CIImage: blurFilter.outputImage!);
        let final = NSImage(size: box.size);
        final.addRepresentation(rep);

        // actually draw the contents to the layer.
        XUIGraphicsPushContext(ctx);
        let frame = NSRect(origin: NSPoint.zero, size: self.frame.size);
        final.drawInRect(frame, fromRect: frame, operation: .Copy, fraction: 1.0);
        XUIGraphicsPopContext();
    }
}
