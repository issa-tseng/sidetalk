
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
    public func makeIterator() -> AnyIterator<AnyObject> {
        var index = -1;
        let maxIndex = CFArrayGetCount(self);
        return AnyIterator {
            index += 1;
            guard index < maxIndex else { return nil; };
            let unmanagedObject: UnsafeRawPointer = CFArrayGetValueAtIndex(self, index);
            return unsafeBitCast(unmanagedObject, to: AnyObject.self);
        };
    }
}
