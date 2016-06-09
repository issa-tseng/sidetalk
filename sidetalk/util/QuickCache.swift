
import Foundation

// TODO: there has to be a cleverer way to do this.
class QuickCache<K: Hashable, V> {
    private var _dict = Dictionary<K, V>();

    func get(key: K, update: (V) -> (), orElse: () -> V) -> V {
        let val = self._dict[key];
        if val != nil {
            update(val!);
            return val!;
        } else {
            let newVal = orElse();
            self._dict[key] = newVal;
            return newVal;
        }
    }

    func get(key: K, orElse: () -> V) -> V { return get(key, update: { _ in }, orElse: orElse); }

    // TODO: there also must be a cleverer way to do this. also a lazier way.
    func all() -> [V] {
        var result = Array<V>();
        for (_, v) in self._dict {
            result.append(v);
        }
        return result;
    }
}
