
import Foundation
import ReactiveCocoa
import enum Result.NoError

extension Signal {
    // HACK: this causes observation to happen! careful with use on cold signals.
    func combineWithDefault<U>(_ other: Signal<U, ReactiveCocoa.Error>, defaultValue: U) -> Signal<(Value, U), ReactiveCocoa.Error> {
        let (signal, observer) = Signal<U, ReactiveCocoa.Error>.pipe();
        let result = self.combineLatestWith(signal);
        other.observe(observer);
        observer.sendNext(defaultValue);

        return result;
    }

    // HACK: same problem!
    func merge(_ other: Signal<Value, ReactiveCocoa.Error>) -> Signal<Value, ReactiveCocoa.Error> {
        let (signal, observer) = Signal<Value, ReactiveCocoa.Error>.pipe();

        self.observeNext { value in observer.sendNext(value); }
        other.observeNext { value in observer.sendNext(value); }

        return signal;
    }

    func downcastToOptional() -> Signal<Value?, ReactiveCocoa.Error> {
        return self.map({ value in value as Value? });
    }

    func always<U>(_ value: U) -> Signal<U, ReactiveCocoa.Error> {
        return self.map({ _ in value });
    }

    // pulled forward from a future version of RAC. See #2952 on their repo.
    public func debounce(_ interval: TimeInterval, onScheduler scheduler: DateSchedulerType) -> Signal<Value, ReactiveCocoa.Error> {
        precondition(interval >= 0)

		return self
			.materialize()
			.flatMap(.latest) { event -> SignalProducer<Event<Value, ReactiveCocoa.Error>, NoError> in
				if event.isTerminating {
					return SignalProducer(value: event).observeOn(scheduler)
				} else {
					return SignalProducer(value: event).delay(interval, onScheduler: scheduler)
				}
			}
			.dematerialize()
	}
}
