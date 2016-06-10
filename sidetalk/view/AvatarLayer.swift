
import Foundation
import Cocoa
import ReactiveCocoa

class CAAvatarLayer : CALayer {
    let fallbackTextAttr = [
        NSForegroundColorAttributeName: NSColor.whiteColor(),
        NSKernAttributeName: -0.2,
        NSFontAttributeName: NSFont.systemFontOfSize(30)
    ];
    let fallbackTextOrigin = CGPoint(x: 12, y: 6);

    var _contact: Contact?;
    var contact: Contact? {
        get { return self._contact; }
        set {
            self._contact = newValue;
            self.rebind();
        }
    }

    private var _image: NSImage?;
    private var _fallback: NSString?;

    private var _observers: [Disposable] = [];

    func rebind() {
        for observer in self._observers { observer.dispose(); }
        if self.contact != nil {
            self._observers = [
                self.contact!.avatar.startWithNext { image in
                    self._image = image;
                    dispatch_async(dispatch_get_main_queue(), { self.setNeedsDisplay(); });
                }/*,
                self.contact!.initials.observeNext { fallback in
                    self._fallback = fallback;
                    self.setNeedsDisplay();
                }*/
            ];
        } else {
            self._observers = [];
        }
    }

    override func drawInContext(ctx: CGContext) {
        self.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;

        // prepare avatar
        let avatarBounds = CGRect(origin: CGPoint.zero, size: self.frame.size);

        // prepare and clip
        XUIGraphicsPushContext(ctx);
        let nsPath = NSBezierPath();
        nsPath.appendBezierPathWithRoundedRect(avatarBounds,
                                               xRadius: self.frame.size.width / 2,
                                               yRadius: self.frame.size.height / 2);
        nsPath.addClip();

        if self._image == nil {
            // render bg
            NSColor.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.8).set();
            NSRectFillUsingOperation(avatarBounds, .CompositeSourceOver);

            // render text
            self.contact!.initials.drawAtPoint(fallbackTextOrigin, withAttributes: fallbackTextAttr);
        } else {
            let image = self._image!;
            image.resizingMode = .Stretch;
            image.drawInRect(avatarBounds, fromRect: CGRect.init(origin: CGPoint.zero, size: image.size), operation: .CompositeSourceOver, fraction: 0.9);
        }

        XUIGraphicsPopContext();
    }
}
