
import Foundation
import ReactiveCocoa
import enum Result.NoError

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

    func downcastToOptional() -> Signal<Value?, Error> {
        return self.map({ value in value as Value? });
    }

    // pulled forward from a future version of RAC. See #2952 on their repo.
    public func debounce(interval: NSTimeInterval, onScheduler scheduler: DateSchedulerType) -> Signal<Value, Error> {
        precondition(interval >= 0)

		return self
			.materialize()
			.flatMap(.Latest) { event -> SignalProducer<Event<Value, Error>, NoError> in
				if event.isTerminating {
					return SignalProducer(value: event).observeOn(scheduler)
				} else {
					return SignalProducer(value: event).delay(interval, onScheduler: scheduler)
				}
			}
			.dematerialize()
	}
}
