
import Foundation

func animationWithDuration(duration: NSTimeInterval, _ block: () -> ()) {
    NSAnimationContext.beginGrouping();
    NSAnimationContext.currentContext().duration = duration;
    block();
    NSAnimationContext.endGrouping();
}

func ceil(size: CGSize) -> CGSize {
    return CGSize(width: ceil(size.width), height: ceil(size.height));
}
