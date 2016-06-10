
import Foundation
import Cocoa

class ContactTile : NSView {
    let contact: Contact;
    let size: CGSize;

    let avatarLayer: CAAvatarLayer
    let outlineLayer: CAShapeLayer
    let textboxLayer: CAShapeLayer
    let textLayer: CATextLayer

    init(frame: CGRect, size: CGSize, contact: Contact) {
        // save props.
        self.contact = contact;
        self.size = size;

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

        // prep future states
        self.prepare();
    }

    private func drawAll() {
        // base overall layout on our size.
        let avatarLength = self.size.height - 2;
        let avatarHalf = avatarLength / 2;
        let origin = CGPoint(x: self.size.width - self.size.height + 1, y: 1);

        // set up avatar layout.
        let avatarSize = CGSize(width: avatarLength, height: avatarLength);
        let avatarBounds = CGRect(origin: origin, size: avatarSize);

        // set up avatar.
        self.avatarLayer.frame = NSRect(origin: origin, size: NSSize(width: avatarLength, height: avatarLength));

        // set up status ring.
        let outlinePath = NSBezierPath(roundedRect: avatarBounds, xRadius: avatarHalf, yRadius: avatarHalf);
        self.outlineLayer.path = outlinePath.CGPath;
        self.outlineLayer.fillColor = NSColor.clearColor().CGColor;
        self.outlineLayer.strokeColor = NSColor.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.2).CGColor; //NSColor.init(red: 0.027, green: 0.785, blue: 0.746, alpha: 0.95).CGColor;
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

    private func prepare() {
        // adjust avatar opacity based on composite presence
        self.contact.online.combineLatestWith(self.contact.presence).observeNext { (online, presence) in
            dispatch_async(dispatch_get_main_queue(), {
                if online {
                    if presence == nil {
                        self.avatarLayer.opacity = 0.9;
                    } else {
                        self.avatarLayer.opacity = 0.5;
                    }
                } else {
                    self.avatarLayer.opacity = 0.1;
                }
            });
        }

        // load avatar
        self.contact.avatar.startWithNext { image in dispatch_async(dispatch_get_main_queue(), { self.avatarLayer.image = image; }); };
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
