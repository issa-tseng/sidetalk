
import Foundation

func animationWithDuration(duration: TimeInterval, _ block: () -> ()) {
    NSAnimationContext.beginGrouping();
    NSAnimationContext.current.duration = duration;
    block();
    NSAnimationContext.endGrouping();
}

func ceil(_ size: CGSize) -> CGSize {
    return CGSize(width: ceil(size.width), height: ceil(size.height));
}
