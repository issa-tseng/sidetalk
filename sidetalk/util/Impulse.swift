
import Foundation

protocol Impulsable {
    static func noopValue() -> Self;
}

internal class ImpulseGenerator<T: Impulsable> {
    private var sid = 0;

    internal init(_ type: T.Type) { }

    func create(value: T) -> Impulse<T> {
        self.sid += 1;
        return Impulse(value, sid: self.sid);
    }
}

internal class ImpulseTracker<T: Impulsable> {
    private var sid = -1;
    private let type: T.Type;

    internal init(_ type: T.Type) {
        self.type = type;
    }

    func extract(impulse: Impulse<T>?) -> T {
        if impulse == nil || self.sid >= impulse!.sid {
            return self.type.noopValue();
        } else {
            self.sid = impulse!.sid;
            return impulse!.value;
        }
    }
}

class Impulse<T: Impulsable> {
    private let sid: Int;
    private let value: T;

    private init(_ value: T, sid: Int) {
        self.value = value;
        self.sid = sid;
    }

    static func generate(type: T.Type) -> ImpulseGenerator<T> {
        return ImpulseGenerator(type);
    }

    static func track(type: T.Type) -> ImpulseTracker<T> {
        return ImpulseTracker(type);
    }
}
