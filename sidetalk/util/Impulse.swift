
import Foundation

protocol Impulsable {
    static func noopValue() -> Self;
}

internal class ImpulseGenerator<T: Impulsable> {
    private var sid = 0;

    internal init(_ type: T.Type) { }

    func create(_ value: T) -> Impulse<T> {
        self.sid += 1;
        return Impulse(value, sid: self.sid);
    }
}

internal class ImpulseTracker<T: Impulsable> {
    internal var sid = -1;
    internal let type: T.Type;

    internal init(_ type: T.Type) {
        self.type = type;
    }

    func extract(_ impulse: Impulse<T>?) -> T {
        if impulse == nil || self.sid >= impulse!.sid {
            return self.type.noopValue();
        } else {
            self.sid = impulse!.sid;
            return impulse!.value;
        }
    }
}

class Impulse<T: Impulsable> {
    internal let sid: Int;
    internal let value: T;

    internal init(_ value: T, sid: Int) {
        self.value = value;
        self.sid = sid;
    }

    static func generate(_ type: T.Type) -> ImpulseGenerator<T> {
        return ImpulseGenerator(type);
    }

    static func track(_ type: T.Type) -> ImpulseTracker<T> {
        return ImpulseTracker(type);
    }
}
