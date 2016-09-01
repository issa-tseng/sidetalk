
import Foundation

class GradientView: NSView {
    let gradient = NSGradient(startingColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.18), endingColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.02))!;

    override func drawRect(dirtyRect: NSRect) {
        let fullGradient = NSImage(size: self.frame.size, flipped: false) { rect in
            self.gradient.drawInRect(rect, angle: 90);
            return true;
        };

        fullGradient.drawInRect(dirtyRect, fromRect: dirtyRect, operation: .CompositeCopy, fraction: 1.0);
    }
}
