
import Foundation
import Cocoa

// TODO: split into V/VM?
class MainView: NSView {
    internal let connection: Connection;
    private var _contactTiles = QuickCache<Contact, ContactTile>();

    // drawing ks. should these go elsewhere?
    let tileSize = NSSize(width: 200, height: 50);
    let tilePadding = CGFloat(4);

    init(frame: CGRect, connection: Connection) {
        self.connection = connection;
        super.init(frame: frame);

        // render stuff (TODO: should this be called in eg viewDidLoad?)
        self.prepare();
    }

    private func prepare() {
        // draw new contacts as required.
        let tiles = self.connection.contacts.map({ (contacts) -> [ContactTile] in
            contacts.map { contact in self._contactTiles.get(contact, orElse: { self.drawOne(contact); }); };
        });

        // relayout contacts as required. TODO: race condition on ContactTiles being created.
        self.connection.contacts.map({ contacts -> Dictionary<Contact, Int> in
            let availableContacts = contacts.filter({ contact in contact.online && contact.presence != "away" });
            let awayContacts = contacts.filter { contact in contact.online && contact.presence == "away" };
            let offlineContacts = contacts.filter { contact in !contact.online };

            let sorted = availableContacts + awayContacts + offlineContacts;
            var result = Dictionary<Contact, Int>();
            for (idx, contact) in sorted.enumerate() {
                result[contact] = idx;
            }
            return result;
        }).combineLatestWith(tiles).observeNext { sortOrder, tiles in self.layout(tiles, sortOrder: sortOrder) }
    }

    private func drawOne(contact: Contact) -> ContactTile {
        let newTile = ContactTile(
            frame: NSRect(origin: NSPoint.zero, size: tileSize),
            contact: contact
        );
        dispatch_async(dispatch_get_main_queue(), { self.addSubview(newTile); });
        return newTile;
    }

    private func layout(contactTiles: [ContactTile], sortOrder: Dictionary<Contact, Int>) {
        NSLog("relayout");
        dispatch_async(dispatch_get_main_queue(), {
            for tile in contactTiles {
                NSLog("\(tile.contact.displayName) goes to \(sortOrder[tile.contact])");
                tile.frame.origin = NSPoint(
                    x: self.frame.width - self.tileSize.width,
                    y: self.frame.height - ((self.tileSize.height + self.tilePadding) * CGFloat((sortOrder[tile.contact] ?? -2) + 1))
                );
            }
        });
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
