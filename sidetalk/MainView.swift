
import Foundation
import Cocoa

class MainView: NSView {
    let connection: Connection;
    let contactTiles = Array<ContactTile>();

    init(frame: CGRect, connection: Connection) {
        self.connection = connection;
        super.init(frame: frame);

        // render stuff (TODO: should this be called in eg viewDidLoad?)
        self.connection.users.map({ users in
            users.map { user in Contact(xmppUser: user); }
        }).observeNext { contacts in
            self.redraw(contacts);
        }
    }

    private func redraw(contacts: [Contact]) {
        dispatch_async(dispatch_get_main_queue(), {
            // first nuke the old stuff (TODO: eventually relocate+anim)

            // now draw new stuff
            let origin = NSPoint(x: 100, y: 500);
            let tileSize = NSSize(width: 200, height: 50);
            let padding = CGFloat(4);

            for (idx, contact) in contacts.enumerate() {
                let newTile = ContactTile(
                    frame: NSRect(origin: NSPoint(x: origin.x, y: origin.y - ((tileSize.height + padding) * CGFloat(idx))), size: tileSize),
                    contact: contact
                );
                self.addSubview(newTile);
            }
        });
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
