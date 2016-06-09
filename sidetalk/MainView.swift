
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

        // relayout contacts as required.
        self.connection.contacts.map({ contacts -> Dictionary<Contact, Int> in
            let availableContacts = contacts.filter({ contact in contact.online && contact.presence != "away" });
            let awayContacts = contacts.filter { contact in contact.online && contact.presence == "away" };

            let sorted = availableContacts + awayContacts;
            var result = Dictionary<Contact, Int>();
            for (idx, contact) in sorted.enumerate() {
                result[contact] = idx;
            }
            return result;
        }).combinePrevious([:]).combineLatestWith(tiles).observeNext { orders, tiles in self.layout(orders.1, lastOrder: orders.0) }
    }

    private func drawOne(contact: Contact) -> ContactTile {
        let newTile = ContactTile(
            frame: self.frame,
            size: tileSize,
            contact: contact
        );
        dispatch_async(dispatch_get_main_queue(), { self.addSubview(newTile); });
        return newTile;
    }

    private func layout(thisOrder: Dictionary<Contact, Int>, lastOrder: Dictionary<Contact, Int>) {
        NSLog("relayout");
        dispatch_async(dispatch_get_main_queue(), {
            for tile in self._contactTiles.all() {
                let anim = CABasicAnimation.init(keyPath: "position");
                var to: NSPoint; // TODO: mutable. gross.

                let this = thisOrder[tile.contact];
                let last = lastOrder[tile.contact];

                NSLog("\(tile.contact.displayName): \(last) -> \(this)");

                // bail early if nothing is to be done
                if this == last {
                    if this == nil {
                        tile.layer!.position = NSPoint(x: 0, y: -900);
                    }
                    continue;
                }

                if this != nil {
                    // we are animating to a real position
                    let x = self.frame.width - self.tileSize.width;
                    let y = self.frame.height - ((self.tileSize.height + self.tilePadding) * CGFloat((this!) + 1));

                    if last != nil {
                        anim.fromValue = NSValue.init(point: tile.layer!.position);
                    } else {
                        anim.fromValue = NSValue.init(point: NSPoint(x: x + self.tileSize.height, y: y));
                    }
                    to = NSPoint(x: x, y: y);
                } else {
                    // we are animating offscreen
                    anim.fromValue = NSValue.init(point: tile.layer!.position);
                    to = NSPoint(x: tile.layer!.position.x + self.tileSize.height, y: tile.layer!.position.y);
                }

                anim.toValue = NSValue.init(point: to);
                anim.beginTime = CACurrentMediaTime() + (0.02 * Double(this ?? 0));
                tile.layer!.removeAnimationForKey("contacttile-layout");
                tile.layer!.addAnimation(anim, forKey: "contacttile-layout");
                tile.layer!.position = to;
            }
        });
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
