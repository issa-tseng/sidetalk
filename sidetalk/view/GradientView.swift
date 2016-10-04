
import Foundation

class GradientView: NSView {
    let gradient = NSGradient(startingColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.08), endingColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0))!;
    private var buffer: NSImage?;

    override func drawRect(dirtyRect: NSRect) {
        if self.buffer == nil {
            // apparently drawRect gets called per-frame during the fadeout, so draw it once first.
            self.buffer = NSImage(size: self.frame.size, flipped: false) { rect in
                self.gradient.drawInRect(rect, angle: 90);
                return true;
            };
        }
        self.buffer!.drawInRect(dirtyRect, fromRect: dirtyRect, operation: .Copy, fraction: 1.0);
    }
}
