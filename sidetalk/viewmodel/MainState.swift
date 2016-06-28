
import Foundation

enum SimpleMainState { case Inactive, Normal, Searching, Selecting, Chatting, None; };

enum MainState: Impulsable {
    case Inactive;
    case Normal;
    case Searching(String, Int);
    case Selecting(Int);
    case Chatting(Contact);
    case None;

    static func noopValue() -> MainState { return .None; }
    var active: Bool { get { return !(self == .Inactive || self == .None); } };
    var essentially: SimpleMainState { get {
        switch self {
        case .Inactive: return .Inactive;
        case .Normal: return .Normal;
        case .Searching(_, _): return .Searching;
        case .Selecting(_): return .Selecting;
        case .Chatting(_): return .Chatting;
        case .None: return .None;
        }
    } };
}

func ==(lhs: MainState, rhs: MainState) -> Bool {
    switch (lhs, rhs) {
    case (let .Searching(ltext, lidx), let .Searching(rtext, ridx)): return ltext == rtext && lidx == ridx;
    case (let .Selecting(lidx), let .Selecting(ridx)): return lidx == ridx;
    case (let .Chatting(lcontact), let .Chatting(rcontact)): return lcontact == rcontact;
    default: return lhs.essentially == rhs.essentially;
    }
}

func !=(lhs: MainState, rhs: MainState) -> Bool { return !(lhs == rhs); };
