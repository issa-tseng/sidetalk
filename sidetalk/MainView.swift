
import Foundation
import Cocoa

class MainView: NSView {
    let labelTextAttr = [
        NSForegroundColorAttributeName: NSColor.whiteColor(),
        NSKernAttributeName: -0.1,
        NSFontAttributeName: NSFont.systemFontOfSize(10)
    ];

    let outlineLayer: CAShapeLayer
    let textLayer: CATextLayer
    let textboxLayer: CAShapeLayer
    let avatarLayer: CAAvatarLayer

    override init(frame: CGRect) {
        let origin = NSPoint( x: 100, y: 500 );

        // set up avatar layout.
        let avatarLength = CGFloat(48);
        let avatarHalf = avatarLength / 2;
        let avatarSize = CGSize(width: avatarLength, height: avatarLength);
        let avatarBounds = CGRect(origin: origin, size: avatarSize);

        // set up avatar.
        let image = NSImage.init(byReferencingFile: "/Users/cxlt/Code/sidetalk/sidetalk/Resources/test1.png")!
        self.avatarLayer = CAAvatarLayer();
        self.avatarLayer.frame = NSRect(origin: origin, size: NSSize(width: avatarLength, height: avatarLength))
        self.avatarLayer.image = image;

        // set up status ring.
        let outlinePath = NSBezierPath(roundedRect: avatarBounds, xRadius: avatarHalf, yRadius: avatarHalf);
        self.outlineLayer = CAShapeLayer();
        self.outlineLayer.path = outlinePath.CGPath;
        self.outlineLayer.fillColor = NSColor.clearColor().CGColor;
        self.outlineLayer.strokeColor = NSColor.init(red: 0.027, green: 0.785, blue: 0.746, alpha: 0.95).CGColor;
        self.outlineLayer.lineWidth = 2;

        // set up text layout.
        let text = NSAttributedString(string: "Test text", attributes: self.labelTextAttr);
        let textSize = text.size();
        let textOrigin = NSPoint(x: origin.x - 16 - textSize.width, y: origin.y + 3 + textSize.height);
        let textBounds = NSRect(origin: textOrigin, size: textSize);

        // set up text.
        self.textLayer = CATextLayer();
        self.textLayer.position = textOrigin;
        self.textLayer.frame = textBounds;
        self.textLayer.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;
        self.textLayer.string = text;

        // set up textbox.
        let textboxRadius = CGFloat(3);
        let textboxPath = NSBezierPath(roundedRect: textBounds.insetBy(dx: -6, dy: -2), xRadius: textboxRadius, yRadius: textboxRadius);
        self.textboxLayer = CAShapeLayer();
        self.textboxLayer.path = textboxPath.CGPath;
        self.textboxLayer.fillColor = NSColor.blackColor().colorWithAlphaComponent(0.12).CGColor;

        // actually init.
        super.init(frame: frame);
        self.wantsLayer = true;

        // now add the layers
        let layer = self.layer!
        layer.addSublayer(self.avatarLayer);
        layer.addSublayer(self.outlineLayer);
        layer.addSublayer(self.textboxLayer);
        layer.addSublayer(self.textLayer);
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
