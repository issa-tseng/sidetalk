
import Foundation
import ReactiveCocoa

extension Signal {
    // HACK: this causes observation to happen! careful with use on cold signals.
    func combineWithDefault<U>(other: Signal<U, Error>, defaultValue: U) -> Signal<(Value, U), Error> {
        let (signal, observer) = Signal<U, Error>.pipe();
        let result = self.combineLatestWith(signal);
        other.observe(observer);
        observer.sendNext(defaultValue);

        return result;
    }

    // HACK: same problem!
    func merge(other: Signal<Value, Error>) -> Signal<Value, Error> {
        let (signal, observer) = Signal<Value, Error>.pipe();

        self.observeNext { value in observer.sendNext(value); }
        other.observeNext { value in observer.sendNext(value); }

        return signal;
    }
}
