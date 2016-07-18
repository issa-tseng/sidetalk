
import Foundation

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
        if let j = i { return self.array[j]; }
        else         { return nil; }
    }

    var count: Int { get { return self.array.count; } };
}