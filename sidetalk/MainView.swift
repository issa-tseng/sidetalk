
import Foundation
import Cocoa
import ReactiveCocoa

struct LayoutState {
    let order: [ Contact : Int ];
    let myTile: ContactTile?;
    let activated: Bool;
}

// TODO: split into V/VM?
class MainView: NSView {
    internal let connection: Connection;
    private var _contactTiles = QuickCache<Contact, ContactTile>();

    // drawing ks. should these go elsewhere?
    let listPadding = CGFloat(50);
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

        // calculate the correct sort of all contacts.
        let sort = self.connection.contacts.map({ contacts -> [ Contact : Int ] in
            let availableContacts = contacts.filter({ contact in contact.onlineOnce && contact.presenceOnce == nil });
            let awayContacts = contacts.filter { contact in contact.onlineOnce && contact.presenceOnce != nil };

            let sorted = availableContacts + awayContacts;
            var result = Dictionary<Contact, Int>();
            for (idx, contact) in sorted.enumerate() {
                result[contact] = idx;
            }
            return result;
        });

        // also grab our own info.
        let myContact = self.connection.myself
            .filter({ user in user != nil })
            .map({ user in Contact(xmppUser: user!, xmppStream: self.connection.stream); });
        let myContactTile = myContact.map { contact in self.drawOne(contact) };

        // clean up old tiles.
        myContactTile
            .map({ tile in tile as ContactTile? }) // TODO: is there a cleaner way to do this?
            .combinePrevious(nil)
            .observeNext { last, _ in
                if last != nil {
                    dispatch_async(dispatch_get_main_queue(), { last!.removeFromSuperview(); } );
                }
            }

        // relayout as required.
        sort.combineLatestWith(tiles).map { order, _ in order } // (Order)
            .combineLatestWith(myContactTile) // (Order, ContactTile?)
            .combineWithDefault(GlobalInteraction.sharedInstance.activated, defaultValue: false) // ((Order, ContactTile?), Bool)
            .map({ orderTile, activated in LayoutState(order: orderTile.0, myTile: orderTile.1, activated: activated); })
            .combinePrevious(LayoutState(order: [:], myTile: nil, activated: false))
            .observeNext { last, this in self.layout(last, this) }

        // if we are active, show all contact labels.
        tiles.combineLatestWith(GlobalInteraction.sharedInstance.activated)
            .observeNext { (tiles, activated) in tiles.forEach { tile in tile.showLabel = activated; } };

        // if we are active, claim window focus. vice versa.
        GlobalInteraction.sharedInstance.activated.observeNext { activated in
            if activated { NSApplication.sharedApplication().activateIgnoringOtherApps(true); }
            else         { GlobalInteraction.sharedInstance.lastApp?.activateWithOptions(NSApplicationActivationOptions.ActivateIgnoringOtherApps); }
        }
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

    private func layout(lastState: LayoutState, _ thisState: LayoutState) {
        NSLog("relayout");
        dispatch_async(dispatch_get_main_queue(), {
            // deal with self
            if thisState.myTile != nil {
                if (lastState.myTile == nil) || (lastState.activated != thisState.activated) {
                    let tile = thisState.myTile!;
                    let anim = CABasicAnimation.init(keyPath: "position");

                    let y = self.frame.height - self.listPadding * 1.5;
                    let off = NSPoint(x: self.frame.width - self.tileSize.width + (self.tileSize.height * 0.55), y: y);
                    let on =  NSPoint(x: self.frame.width - self.tileSize.width - self.tilePadding, y: y);

                    if (thisState.activated) {
                        anim.fromValue = NSValue.init(point: off);
                        anim.toValue = NSValue.init(point: on);
                    } else {
                        anim.fromValue = NSValue.init(point: on);
                        anim.toValue = NSValue.init(point: off);
                    }

                    if (lastState.myTile == nil) {
                        anim.fromValue = NSValue.init(point: NSPoint(x: self.frame.width, y: y));
                    }

                    anim.duration = thisState.activated ? 0.03 : 0.4;
                    tile.layer!.removeAnimationForKey("contacttile-layout");
                    tile.layer!.addAnimation(anim, forKey: "contacttile-layout");
                    tile.layer!.position = thisState.activated ? on : off;
                }
            }

            // deal with actual contacts
            for tile in self._contactTiles.all() {
                let anim = CABasicAnimation.init(keyPath: "position");
                var to: NSPoint; // TODO: mutable. gross.

                let last = lastState.order[tile.contact];
                let this = thisState.order[tile.contact];

                // make sure we're offscreen if we're not to be shown
                if last == nil && this == nil { tile.layer!.position = NSPoint(x: 0, y: -900); }

                if this != nil {
                    // we are animating to a real position
                    let x = self.frame.width - self.tileSize.width + (thisState.activated ? -(self.tilePadding) : (self.tileSize.height * 0.55));
                    let y = self.frame.height - (self.listPadding * 2) - ((self.tileSize.height + self.tilePadding) * CGFloat((this!) + 1));

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
                anim.duration = NSTimeInterval((!lastState.activated && thisState.activated ? 0.05 : 0.2) + (0.02 * Double(this ?? 0)));
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
