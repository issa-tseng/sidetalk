
import Foundation

func animationWithDuration(duration: NSTimeInterval, _ block: () -> ()) {
    NSAnimationContext.beginGrouping();
    NSAnimationContext.currentContext().duration = duration;
    block();
    NSAnimationContext.endGrouping();
}
