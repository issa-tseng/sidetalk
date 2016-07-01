
import Foundation

extension Array {
    func part(predicate: (Element) -> Bool) -> (Array<Element>, Array<Element>) {
        var a = Array<Element>();
        var b = Array<Element>();

        self.forEach { elem in
            if predicate(elem) { a.append(elem); }
            else               { b.append(elem); }
        };

        return (a, b);
    }

    func find(predicate: (Element) -> Bool) -> Element? {
        for elem in self { if predicate(elem) { return elem; } }
        return nil;
    }
}

// from: http://stackoverflow.com/a/32127187
extension CFArray: SequenceType {
    public func generate() -> AnyGenerator<AnyObject> {
        var index = -1;
        let maxIndex = CFArrayGetCount(self);
        return AnyGenerator {
            index += 1;
            guard index < maxIndex else { return nil; };
            let unmanagedObject: UnsafePointer<Void> = CFArrayGetValueAtIndex(self, index);
            return unsafeBitCast(unmanagedObject, AnyObject.self);
        };
    }
}
