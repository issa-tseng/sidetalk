
import Foundation;
import ReactiveSwift;
import enum Result.NoError;

class Registry {
    private let handle: FileHandle;
    private var _members = Set<String>();

    private let membersSignal = ManagedSignal<Set<String>>();
    var members: Signal<Set<String>, NoError> { get { return self.membersSignal.signal; } };

    init(handle: FileHandle) {
        self.handle = handle;
        self.load();
    }

    func add(_ member: String) { if !self._members.contains(member) { self._add(member); } }
    private func _add(_ member: String) {
        self._members.insert(member);
        DispatchQueue.global(qos: .default).async(execute: { self.membersSignal.observer.send(value: self._members); });
        self.save();
    }

    func contains(member: String) -> Bool { return self._members.contains(member); }

    func remove(_ member: String) { if self._members.contains(member) { self._remove(member); } }
    func _remove(_ member: String) {
        self._members.remove(member);
        DispatchQueue.global(qos: .default).async(execute: { self.membersSignal.observer.send(value: self._members); });
        self.save();
    }

    func toggle(_ member: String) {
        if self._members.contains(member) { self._remove(member); } else { self._add(member); }
    }

    // TODO: this is very clearly a terrible hack. but with RAC working the way it does i don't see an alternative.
    func ping() {
        self.membersSignal.observer.send(value: self._members);
    }

    private func load() {
        self._members.removeAll(keepingCapacity: true);
        let data = self.handle.readDataToEndOfFile();
        if let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            if let array = root as? NSArray {
                for member in array {
                    if let strMember = member as? NSString {
                        self.add(String.init(strMember));
                    }
                }
            }
        } else {
            NSLog("Unable to read property list");
        }
        self.membersSignal.observer.send(value: self._members);
    }

    private func save() {
        let nsmembers = self._members.map({ member in NSString.init(string: member) });
        let root = NSArray.init(array: nsmembers);
        if let data = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            self.handle.truncateFile(atOffset: 0);
            self.handle.write(data);
        } else {
            NSLog("Unable to serialize property list");
        }
    }

    static func create(filename: String) -> Registry? {
        let searchPath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true);
        if let path = searchPath.first {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil);
            } catch {
                NSLog("Unable to create library directory");
            }

            let path = "\(path)/\(filename)";
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil, attributes: nil);
            }
            if let handle = FileHandle.init(forUpdatingAtPath: path) {
                return Registry(handle: handle);
            }
        }
        return nil;
    }


}
