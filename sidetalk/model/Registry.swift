
import Foundation;
import ReactiveCocoa;
import enum Result.NoError;

class Registry {
    private let handle: NSFileHandle;
    private var _members = Set<String>();

    private let membersSignal = ManagedSignal<Set<String>>();
    var members: Signal<Set<String>, NoError> { get { return self.membersSignal.signal; } };

    init(handle: NSFileHandle) {
        self.handle = handle;
        self.load();
    }

    func add(member: String) { if !self._members.contains(member) { self._add(member); } }
    private func _add(member: String) {
        self._members.insert(member);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), { self.membersSignal.observer.sendNext(self._members); });
        self.save();
    }

    func contains(member: String) -> Bool { return self._members.contains(member); }

    func remove(member: String) { if self._members.contains(member) { self._remove(member); } }
    func _remove(member: String) {
        self._members.remove(member);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), { self.membersSignal.observer.sendNext(self._members); });
        self.save();
    }

    func toggle(member: String) {
        if self._members.contains(member) { self._remove(member); } else { self._add(member); }
    }

    // TODO: this is very clearly a terrible hack. but with RAC working the way it does i don't see an alternative.
    func ping() {
        self.membersSignal.observer.sendNext(self._members);
    }

    private func load() {
        self._members.removeAll(keepCapacity: true);
        let data = self.handle.readDataToEndOfFile();
        if let root = try? NSPropertyListSerialization.propertyListWithData(data, options: .Immutable, format: nil) {
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
        self.membersSignal.observer.sendNext(self._members);
    }

    private func save() {
        let nsmembers = self._members.map({ member in NSString.init(string: member) });
        let root = NSArray.init(array: nsmembers);
        if let data = try? NSPropertyListSerialization.dataWithPropertyList(root, format: .BinaryFormat_v1_0, options: 0) {
            self.handle.truncateFileAtOffset(0);
            self.handle.writeData(data);
        } else {
            NSLog("Unable to serialize property list");
        }
    }

    static func create(filename: String) -> Registry? {
        let searchPath = NSSearchPathForDirectoriesInDomains(.ApplicationSupportDirectory, .UserDomainMask, true);
        if let path = searchPath.first {
            do {
                try NSFileManager.defaultManager().createDirectoryAtPath(path, withIntermediateDirectories: true, attributes: nil);
            } catch {
                NSLog("Unable to create library directory");
            }

            let path = "\(path)/\(filename)";
            if !NSFileManager.defaultManager().fileExistsAtPath(path) {
                NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil);
            }
            if let handle = NSFileHandle.init(forUpdatingAtPath: path) {
                return Registry(handle: handle);
            }
        }
        return nil;
    }


}
