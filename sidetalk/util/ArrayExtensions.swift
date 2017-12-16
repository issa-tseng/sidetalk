
import Foundation

extension Array {
    func part(_ predicate: (Element) -> Bool) -> (Array<Element>, Array<Element>) {
        var a = Array<Element>();
        var b = Array<Element>();

        self.forEach { elem in
            if predicate(elem) { a.append(elem); }
            else               { b.append(elem); }
        };

        return (a, b);
    }

    func find(_ predicate: (Element) -> Bool) -> Element? {
        for elem in self { if predicate(elem) { return elem; } }
        return nil;
    }
}

// from: http://stackoverflow.com/a/32127187
extension CFArray: Sequence {
    public struct Iterator: IteratorProtocol {
        var array: NSArray;
        var idx = -1;

        init(_ inArray: NSArray) {
            self.array = inArray as NSArray;
        }
        public mutating func next() -> Any? {
            self.idx += 1;
            guard self.idx < self.array.count else { return nil; }
            return self.array[self.idx];
        }
    }
    
    public func makeIterator() -> CFArray.Iterator {
        return Iterator(self);
    }
}
