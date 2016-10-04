
import Foundation

func animationWithDuration(_ duration: TimeInterval, _ block: () -> ()) {
    NSAnimationContext.beginGrouping();
    NSAnimationContext.current().duration = duration;
    block();
    NSAnimationContext.endGrouping();
}
