
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
}
