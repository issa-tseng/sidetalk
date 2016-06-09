
import Foundation
import Cocoa

class ContactTile : NSView {
    let contact: Contact;

    let avatarLayer: CAAvatarLayer
    let outlineLayer: CAShapeLayer
    let textboxLayer: CAShapeLayer
    let textLayer: CATextLayer

    init(frame: CGRect, contact: Contact) {
        // save contact.
        self.contact = contact;

        // create layers.
        self.avatarLayer = CAAvatarLayer(); // TODO: maybe just render a different layer class?
        self.outlineLayer = CAShapeLayer();
        self.textLayer = CATextLayer();
        self.textboxLayer = CAShapeLayer();

        // actually init.
        super.init(frame: frame);
        self.wantsLayer = true;

        // now draw everything, and add the layers.
        dispatch_async(dispatch_get_main_queue(), {
            self.drawAll();

            let layer = self.layer!
            layer.addSublayer(self.avatarLayer);
            layer.addSublayer(self.outlineLayer);
            layer.addSublayer(self.textboxLayer);
            layer.addSublayer(self.textLayer);
        });
    }

    private func drawAll() {
        // base overall layout on our frame.
        let avatarLength = frame.height - 2;
        let avatarHalf = avatarLength / 2;
        let origin = CGPoint(x: frame.width - frame.height + 1, y: 1);

        // set up avatar layout.
        let avatarSize = CGSize(width: avatarLength, height: avatarLength);
        let avatarBounds = CGRect(origin: origin, size: avatarSize);

        // set up avatar.
        if self.contact.avatarSource == nil {
            // render backup.
        } else {
            let image = NSImage.init(byReferencingFile: contact.avatarSource!)! // TODO: maybe let it handle the source?
            self.avatarLayer.frame = NSRect(origin: origin, size: NSSize(width: avatarLength, height: avatarLength))
            self.avatarLayer.image = image;
        }

        // set up status ring.
        let outlinePath = NSBezierPath(roundedRect: avatarBounds, xRadius: avatarHalf, yRadius: avatarHalf);
        self.outlineLayer.path = outlinePath.CGPath;
        self.outlineLayer.fillColor = NSColor.clearColor().CGColor;
        self.outlineLayer.strokeColor = NSColor.init(red: 0.027, green: 0.785, blue: 0.746, alpha: 0.95).CGColor;
        self.outlineLayer.lineWidth = 2;

        // set up text layout.
        let text = NSAttributedString(string: contact.displayName ?? "unknown", attributes: Common.labelTextAttr);
        let textSize = text.size();
        let textOrigin = NSPoint(x: origin.x - 16 - textSize.width, y: origin.y + 3 + textSize.height);
        let textBounds = NSRect(origin: textOrigin, size: textSize);

        // set up text.
        self.textLayer.position = textOrigin;
        self.textLayer.frame = textBounds;
        self.textLayer.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;
        self.textLayer.string = text;

        // set up textbox.
        let textboxRadius = CGFloat(3);
        let textboxPath = NSBezierPath(roundedRect: textBounds.insetBy(dx: -6, dy: -2), xRadius: textboxRadius, yRadius: textboxRadius);
        self.textboxLayer.path = textboxPath.CGPath;
        self.textboxLayer.fillColor = NSColor.blackColor().colorWithAlphaComponent(0.2).CGColor;
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
