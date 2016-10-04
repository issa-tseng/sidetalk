
import Foundation

enum SimpleMainState { case inactive, normal, searching, selecting, chatting, none; };

indirect enum MainState: Impulsable {
    case inactive;
    case normal;
    case searching(String, Int);
    case selecting(Int);
    case chatting(Contact, MainState);
    case none;

    static func noopValue() -> MainState { return .none; }
    var active: Bool { get { return !(self == .inactive || self == .none); } };
    var essentially: SimpleMainState { get {
        switch self {
        case .inactive: return .inactive;
        case .normal: return .normal;
        case .searching(_, _): return .searching;
        case .selecting(_): return .selecting;
        case .chatting(_, _): return .chatting;
        case .none: return .none;
        }
    } };
}

func ==(lhs: MainState, rhs: MainState) -> Bool {
    switch (lhs, rhs) {
    case (let .searching(ltext, lidx), let .searching(rtext, ridx)): return ltext == rtext && lidx == ridx;
    case (let .selecting(lidx), let .selecting(ridx)): return lidx == ridx;
    case (let .chatting(lcontact, _), let .chatting(rcontact, _)): return lcontact == rcontact;
    default: return lhs.essentially == rhs.essentially;
    }
}

func !=(lhs: MainState, rhs: MainState) -> Bool { return !(lhs == rhs); };
