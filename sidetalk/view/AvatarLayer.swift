
import Foundation
import Cocoa
import ReactiveCocoa

class CAAvatarLayer : CALayer {
    var _contact: Contact?;
    var contact: Contact? {
        get { return self._contact; }
        set {
            self._contact = newValue;
            self.rebind();
        }
    }

    fileprivate var _image: NSImage?;
    fileprivate var _fallback: NSString?;

    fileprivate var _observers: [Disposable] = [];

    func rebind() {
        for observer in self._observers { observer.dispose(); }
        if self.contact != nil {
            self._observers = [
                self.contact!.avatar.startWithNext { image in
                    self._image = image;
                    DispatchQueue.main.async(execute: { self.setNeedsDisplay(); });
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

    override func draw(in ctx: CGContext) {
        self.contentsScale = NSScreen.main()!.backingScaleFactor;

        // prepare avatar
        let avatarBounds = CGRect(origin: CGPoint.zero, size: self.frame.size);

        // prepare and clip
        XUIGraphicsPushContext(ctx);
        let nsPath = NSBezierPath();
        nsPath.appendRoundedRect(avatarBounds,
                                               xRadius: self.frame.size.width / 2,
                                               yRadius: self.frame.size.height / 2);
        nsPath.addClip();

        if self._image == nil {
            // render bg
            NSColor.init(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.8).set();
            NSRectFillUsingOperation(avatarBounds, .sourceOver);

            // render text
            NSGraphicsContext.saveGraphicsState();
            NSGraphicsContext.setCurrent(NSGraphicsContext.init(cgContext: ctx, flipped: false));
            self.contact!.initials.draw(in: ST.avatar.fallbackTextFrame, withAttributes: ST.avatar.fallbackTextAttr);
            NSGraphicsContext.restoreGraphicsState();
        } else {
            let image = self._image!;
            image.resizingMode = .stretch;
            image.draw(in: avatarBounds, from: CGRect.init(origin: CGPoint.zero, size: image.size), operation: .sourceOver, fraction: 0.9);
        }

        XUIGraphicsPopContext();
    }
}
