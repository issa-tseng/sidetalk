
import Foundation

class GradientView: NSView {
    let gradient = NSGradient(starting: NSColor(red: 0, green: 0, blue: 0, alpha: 0.08), ending: NSColor(red: 0, green: 0, blue: 0, alpha: 0))!;
    fileprivate var buffer: NSImage?;

    override func draw(_ dirtyRect: NSRect) {
        if self.buffer == nil {
            // apparently drawRect gets called per-frame during the fadeout, so draw it once first.
            self.buffer = NSImage(size: self.frame.size, flipped: false) { rect in
                self.gradient.draw(in: rect, angle: 90);
                return true;
            };
        }
        self.buffer!.draw(in: dirtyRect, from: dirtyRect, operation: .copy, fraction: 1.0);
    }
}
