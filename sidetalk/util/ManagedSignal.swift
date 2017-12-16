
import Foundation;
import ReactiveSwift;
import enum Result.NoError;

class ManagedSignal<T> {
    private let _signal: Signal<T, NoError>;
    private let _observer: Signal<T, NoError>.Observer;

    var signal: Signal<T, NoError> { get { return self._signal; } }
    var observer: Signal<T, NoError>.Observer { get { return self._observer; } }

    init() {
        (self._signal, self._observer) = Signal<T, NoError>.pipe();
    }
}
