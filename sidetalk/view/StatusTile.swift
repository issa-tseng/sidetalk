
import Foundation;
import ReactiveSwift;
import enum Result.NoError;

class StatusTile: NSView {
    internal let connection: Connection;

    private let _searchField: NSTextField;
    private let _searchIcon: IconView;
    private let _presenceIndicator: PresenceIndicator;
    private let _shadowLayer = ShadowLayer();

    private let _searchLeecher: STTextDelegate;
    var searchText: Signal<String, NoError> { get { return self._searchLeecher.text; } };

    private let _ownPresence: ManagedSignal<Presence>; // TODO: temporary until i unify presence into contact.
    var ownPresence: Signal<Presence, NoError> { get { return self._ownPresence.signal; } };
    
    private let _contactTile = ManagedSignal<ContactTile?>();
    var contactTile: Signal<ContactTile?, NoError> { get { return self._contactTile.signal; } };

    let tileSize = NSSize(width: 300, height: 50);
    let iconMargin = CGFloat(42);
    let searchFrame = NSRect(origin: NSPoint(x: 30, y: 8 + 42), size: NSSize(width: 212, height: 30));
    let presenceIndicatorOrigin = NSPoint(x: 250, y: 5 + 42);

    init(connection: Connection, frame: NSRect) {
        self.connection = connection;

        self._searchField = NSTextField(frame: searchFrame);
        self._searchField.backgroundColor = NSColor.clear;
        self._searchField.isBezeled = false;
        self._searchField.focusRingType = NSFocusRingType.none;
        self._searchField.textColor = NSColor.white;
        self._searchField.font = NSFont.systemFont(ofSize: 20);
        self._searchField.alignment = NSTextAlignment.right;
        self._searchField.lineBreakMode = .byTruncatingHead;
        self._searchField.alphaValue = 0.0;
        self._searchLeecher = STTextDelegate(field: self._searchField);

        let searchIconLayer = RoundIconLayer();
        self._searchIcon = IconView(
            layer: searchIconLayer,
            frame: NSRect(origin: NSPoint(x: tileSize.width - tileSize.height, y: self.iconMargin), size: NSSize(width: tileSize.height, height: tileSize.height))
        );
        searchIconLayer.opacity = 0.0;
        searchIconLayer.image = NSImage.init(named: NSImage.Name.init(rawValue: "search"));

        let presence = ManagedSignal<Presence>();
        self._ownPresence = presence;
        self._presenceIndicator = PresenceIndicator(presenceSignal: presence.signal, initial: .None, frame: NSRect(origin: presenceIndicatorOrigin, size: frame.size));

        super.init(frame: frame);
    }

    required init(coder: NSCoder) {
        fatalError("no coder for you");
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMove(toSuperview: newSuperview);

        // add calayers directly.
        let radius: CGFloat = 8;
        self._shadowLayer.frame = NSRect(origin: NSPoint(x: searchFrame.origin.x - (3 * radius), y: searchFrame.origin.y - radius),
                                        size: NSSize(width: searchFrame.width + (6 * radius), height: searchFrame.height + (2.5 * radius)));
        self._shadowLayer.radius = radius;
        self._shadowLayer.opacity = 0.18;
        self.layer!.addSublayer(self._shadowLayer);

        // add full subviews.
        self.addSubview(self._searchField);
        self.addSubview(self._searchIcon);
        self.addSubview(self._presenceIndicator);
    }

    func prepare(_ mainView: MainView) {
        // grab and render our own info.
        self.connection.myself
            .filter({ contact in contact != nil })
            .map({ contact in contact! })
            .observeValues({ contact in
                DispatchQueue.main.async(execute: { self._contactTile.observer.send(value: self.drawContact(contact)); });
            });

        // if we must, clean up the old tile.
        self.contactTile
            .combinePrevious(nil)
            .observeValues { last, _ in
                if last != nil { DispatchQueue.main.async(execute: { last!.removeFromSuperview(); } ); }
            };

        // focus textfield if activated. clear it if deactivated.
        mainView.state.combinePrevious(.Inactive).observeValues { (last, this) in
            if last == this { return; }

            if this == .Normal || this.essentially == .Selecting {
                DispatchQueue.main.async(execute: {
                    self._searchField.stringValue = "";
                    self.window!.makeFirstResponder(self._searchField);
                });
            }
        };

        // show textfield and search icon if there is content.
        self.searchText.observeValues { text in DispatchQueue.main.async(execute: {
            let hasContent = !text.isEmpty;
            self._searchField.alphaValue = hasContent ? 1.0 : 0.0;
            self._searchIcon.iconLayer.opacity = hasContent ? 1.0 : 0.0;
        }); };

        // update our shadow layer when the text changes.
        self.searchText.observeValues { text in
            let width = NSAttributedString(string: text, attributes: [ NSAttributedStringKey.font: NSFont.systemFont(ofSize: 20) ]).size().width;
            self._shadowLayer.width = width;
        };

        // update our presence when network connectivity changes (TODO: temporary until unified?)
        self.connection.authenticated
            .combineWithDefault(self.connection.hasInternet, defaultValue: true)
            .observeValues { auth, online in
                switch (auth, online) {
                case (false, _): self._ownPresence.observer.send(value: .None);
                case (true, false): self._ownPresence.observer.send(value: .Offline);
                case (true, true): self._ownPresence.observer.send(value: .Online);
                };
            };
    }

    private func drawContact(_ contact: Contact) -> ContactTile {
        let tile = ContactTile(
            frame: NSRect(origin: NSPoint.init(x: 0, y: self.iconMargin), size: self.tileSize),
            contact: contact
        );
        DispatchQueue.main.async(execute: {
            self.addSubview(tile);
            self.sendSubview(toBack: tile);
        });
        return tile;
    }
}
