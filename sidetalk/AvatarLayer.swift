
import Foundation
import Cocoa

class CAAvatarLayer : CALayer {
    var _image: NSImage?;
    var image: NSImage? {
        get { return self._image; }
        set {
            self._image = newValue;
            self.setNeedsDisplay();
        }
    }

    override func drawInContext(ctx: CGContext) {
        if self.image == nil { return };
        let image = self.image!

        // basic setup
        self.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;

        // prepare avatar
        let avatarBounds = CGRect(origin: CGPoint.zero, size: self.frame.size);
        image.resizingMode = .Stretch;

        // render avatar
        XUIGraphicsPushContext(ctx);
        let nsPath = NSBezierPath();
        nsPath.appendBezierPathWithRoundedRect(avatarBounds,
                                               xRadius: self.frame.size.width / 2,
                                               yRadius: self.frame.size.height / 2);
        nsPath.addClip();
        image.drawInRect(avatarBounds, fromRect: CGRect.init(origin: CGPoint.zero, size: image.size), operation: .CompositeSourceOver, fraction: 0.9);
        //image.drawInRect(avatarBounds, fromRect: CGRect.init(origin: CGPoint.zero, size: image.size), operation: .CompositeCopy, fraction: 0.9);
        XUIGraphicsPopContext();
    }
}
