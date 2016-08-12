
import Foundation
import Cocoa

extension NSView {
    func ancestors() -> [NSView] {
        if let superview = self.superview {
            return superview.ancestors() + [ self ];
        } else {
            return [ self ];
        }
    }
}
