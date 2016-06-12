
import Foundation
import ReactiveCocoa

class StatusTile: NSView {
    internal let connection: Connection;

    let tileSize = NSSize(width: 300, height: 50);

    init(connection: Connection, frame: NSRect) {
        self.connection = connection;
        super.init(frame: frame);
    }

    required init(coder: NSCoder) {
        fatalError("no coder for you");
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(newSuperview);
        self.prepare();
    }

    func prepare() {
        // grab and render our own info.
        self.connection.myself
            .filter({ user in user != nil })
            .map({ user in Contact(xmppUser: user!, xmppStream: self.connection.stream); })

            // render the tile.
            .map { contact in self.drawContact(contact) } // HACK: side effects in a map.

            // clean up old tiles.
            .map({ tile in tile as ContactTile? }) // TODO: is there a cleaner way to do this?
            .combinePrevious(nil)
            .observeNext { last, _ in
                if last != nil {
                    dispatch_async(dispatch_get_main_queue(), { last!.removeFromSuperview(); } );
                }
            };
    }

    func drawContact(contact: Contact) -> ContactTile {
        let tile = ContactTile(
            frame: NSRect(origin: NSPoint.zero, size: self.tileSize),
            size: self.tileSize,
            contact: contact
        );
        dispatch_async(dispatch_get_main_queue(), { NSLog("ADDING CONTACT"); self.addSubview(tile); });
        return tile;
    }
}
