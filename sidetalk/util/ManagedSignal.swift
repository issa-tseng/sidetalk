
import Foundation
import ReactiveCocoa
import enum Result.NoError

class ManagedSignal<T> {
    private let _signal: Signal<T, NoError>;
    private let _observer: Observer<T, NoError>;

    var signal: Signal<T, NoError> { get { return self._signal; } }
    var observer: Observer<T, NoError> { get { return self._observer; } }

    init() {
        (self._signal, self._observer) = Signal<T, NoError>.pipe();
    }
}

