
import Foundation

struct Clamped {
    let idx: Int?;
    init(_ idx: Int?) { self.idx = idx; }
}

// it goes both ways.
class SortOf<T: Hashable> {
    let array: [T];
    let dict: [T : Int];

    init(_ array: [T]) {
        self.array = array;

        var mutDict = [T : Int]();
        for (idx, obj) in array.enumerate() { mutDict[obj] = idx; }
        self.dict = mutDict;
    }

    convenience init() { self.init(Array<T>()); }

    subscript(x: T?) -> Int? {
        if let y = x { return self.dict[y]; }
        else         { return nil; }
    }
    subscript(i: Int?) -> T? {
        if let j = i { if j < self.count && self.count > 0 { return self.array[j]; }
                       else { return nil; } }
        else         { return nil; }
    }
    subscript(c: Clamped) -> T? {
        if self.count == 0      { return nil; }
        else if let i = c.idx   { return self[min(i, self.count - 1)]; }
        else                    { return nil; }
    }

    var count: Int { get { return self.array.count; } };
}
