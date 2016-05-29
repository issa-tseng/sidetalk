
import Foundation
import Cocoa

class MainView: NSView {
    let labelTextAttr = [
        NSForegroundColorAttributeName: NSColor.whiteColor(),
        NSKernAttributeName: -0.1,
        NSFontAttributeName: NSFont.systemFontOfSize(10)
    ];

    override func drawRect(dirtyRect: NSRect) {
        let avatarSize = CGFloat(48);
        let avatarHalf = avatarSize / 2;

        let text = NSString.init(string: "Test text");
        let origin = NSPoint( x: 100, y: 500 );

        // figure out text footprint
        let textSize = text.sizeWithAttributes(self.labelTextAttr);
        let textOrigin = NSPoint( x: origin.x - avatarHalf - textSize.width - 16, y: origin.y - (textSize.height / 2) );
        let textBounds = CGRect( origin: textOrigin, size: textSize );

        // render label background
        let labelPath = NSBezierPath();
        labelPath.appendBezierPathWithRoundedRect(textBounds.insetBy( dx: -8, dy: -4 ), xRadius: 10, yRadius: 10);
        NSColor.blackColor().colorWithAlphaComponent(0.12).set();
        labelPath.fill();

        // render text label
        text.drawAtPoint(textOrigin, withAttributes: self.labelTextAttr);

        // prepare avatar
        let image = NSImage.init(byReferencingFile: "/Users/cxlt/Code/sidetalk/sidetalk/Resources/test1.png")!
        let avatarBounds = CGRect( x: origin.x - avatarHalf, y: origin.y - avatarHalf, width: avatarSize, height: avatarSize);
        image.resizingMode = .Stretch;

        // render avatar
        NSGraphicsContext.saveGraphicsState();
        let avatarPath = NSBezierPath();
        avatarPath.appendBezierPathWithRoundedRect(avatarBounds, xRadius: avatarHalf, yRadius: avatarHalf);
        avatarPath.addClip();
        image.drawInRect(avatarBounds, fromRect: CGRect.init(origin: CGPoint.zero, size: image.size), operation: .CompositeSourceOver, fraction: 0.9);
        NSGraphicsContext.restoreGraphicsState();

        // render outline
        let outlinePath = NSBezierPath();
        outlinePath.lineWidth = 2;
        outlinePath.appendBezierPathWithRoundedRect(avatarBounds, xRadius: avatarHalf, yRadius: avatarHalf);
        NSColor.init(red: 0.027, green: 0.785, blue: 0.746, alpha: 0.95).set();
        outlinePath.stroke();
    }
}
