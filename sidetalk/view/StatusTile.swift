
import Foundation;
import ReactiveCocoa;
import enum Result.NoError;

class StatusTile: NSView {
    internal let connection: Connection;

    private let _searchField: NSTextField;
    private let _searchIcon: IconView;
    private let _hiddenModeIcon: IconView;
    private let _muteModeIcon: IconView;
    private let _presenceIndicator: PresenceIndicator;
    private let _shadowLayer = ShadowLayer();

    private let _searchLeecher: STTextDelegate;
    var searchText: Signal<String, NoError> { get { return self._searchLeecher.text; } };

    private let _ownPresence: ManagedSignal<Presence>; // TODO: temporary until i unify presence into contact.
    var ownPresence: Signal<Presence, NoError> { get { return self._ownPresence.signal; } };

    let tileSize = NSSize(width: 300, height: 50);
    let iconMargin = CGFloat(42);
    let iconSize = CGFloat(20);
    let icon1Y = CGFloat(20);
    let icon2Y = CGFloat(0);
    let searchFrame = NSRect(origin: NSPoint(x: 30, y: 8 + 42), size: NSSize(width: 212, height: 30));
    let presenceIndicatorOrigin = NSPoint(x: 250, y: 5 + 42);

    init(connection: Connection, frame: NSRect) {
        self.connection = connection;

        self._searchField = NSTextField(frame: searchFrame);
        self._searchField.backgroundColor = NSColor.clearColor();
        self._searchField.bezeled = false;
        self._searchField.focusRingType = NSFocusRingType.None;
        self._searchField.textColor = NSColor.whiteColor();
        self._searchField.font = NSFont.systemFontOfSize(20);
        self._searchField.alignment = NSTextAlignment.Right;
        self._searchField.lineBreakMode = .ByTruncatingHead;
        self._searchField.alphaValue = 0.0;
        self._searchLeecher = STTextDelegate(field: self._searchField);

        let searchIconLayer = RoundIconLayer();
        self._searchIcon = IconView(
            layer: searchIconLayer,
            frame: NSRect(origin: NSPoint(x: tileSize.width - tileSize.height, y: self.iconMargin), size: NSSize(width: tileSize.height, height: tileSize.height))
        );
        searchIconLayer.opacity = 0.0;
        searchIconLayer.image = NSImage.init(named: "search");

        let hiddenIconLayer = IconLayer();
        self._hiddenModeIcon = IconView(
            layer: hiddenIconLayer,
            frame: NSRect(origin: NSPoint(x: tileSize.width - tileSize.height + 6, y: self.icon1Y), size: NSSize(width: iconSize, height: iconSize))
        );
        self._hiddenModeIcon.alphaValue = 0.0;
        hiddenIconLayer.image = NSImage.init(named: "hidden");

        let muteIconLayer = IconLayer();
        self._muteModeIcon = IconView(
            layer: muteIconLayer,
            frame: NSRect(origin: NSPoint(x: tileSize.width - tileSize.height + 6, y: self.icon1Y), size: NSSize(width: iconSize, height: iconSize))
        );
        self._muteModeIcon.alphaValue = 0.0;
        muteIconLayer.image = NSImage.init(named: "mute");

        let presence = ManagedSignal<Presence>();
        self._ownPresence = presence;
        self._presenceIndicator = PresenceIndicator(presenceSignal: presence.signal, initial: .None, frame: NSRect(origin: presenceIndicatorOrigin, size: frame.size));

        super.init(frame: frame);
    }

    required init(coder: NSCoder) {
        fatalError("no coder for you");
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMoveToSuperview(newSuperview);

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
        self.addSubview(self._hiddenModeIcon);
        self.addSubview(self._muteModeIcon);
        self.addSubview(self._presenceIndicator);
    }

    func prepare(mainView: MainView) {
        // grab and render our own info.
        self.connection.myself
            .filter({ contact in contact != nil })
            .map({ contact in contact! })

            // render the tile.
            .map { contact in self.drawContact(contact) } // HACK: side effects in a map.

            // clean up old tiles.
            .map({ tile in tile as ContactTile? }) // TODO: is there a cleaner way to do this?
            .combinePrevious(nil)
            .observeNext { last, _ in
                if last != nil { dispatch_async(dispatch_get_main_queue(), { last!.removeFromSuperview(); } ); }
            };

        // focus textfield if activated. clear it if deactivated.
        mainView.state.combinePrevious(.Inactive).observeNext { (last, this) in
            if last == this { return; }

            if this == .Normal || this.essentially == .Selecting {
                dispatch_async(dispatch_get_main_queue(), {
                    self._searchField.stringValue = "";
                    self.window!.makeFirstResponder(self._searchField);
                });
            }
        };

        // show textfield and search icon if there is content.
        self.searchText.observeNext { text in dispatch_async(dispatch_get_main_queue(), {
            let hasContent = text.characters.count > 0;
            self._searchField.alphaValue = hasContent ? 1.0 : 0.0;
            self._searchIcon.iconLayer.opacity = hasContent ? 1.0 : 0.0;
        }); };

        // update our shadow layer when the text changes.
        self.searchText.observeNext { text in
            let width = NSAttributedString(string: text, attributes: [ NSFontAttributeName: NSFont.systemFontOfSize(20) ]).size().width;
            self._shadowLayer.width = width;
        };

        // update our presence when network connectivity changes (TODO: temporary until unified?)
        self.connection.authenticated
            .combineWithDefault(self.connection.hasInternet, defaultValue: true)
            .observeNext { auth, online in
                switch (auth, online) {
                case (false, _): self._ownPresence.observer.sendNext(.None);
                case (true, false): self._ownPresence.observer.sendNext(.Offline);
                case (true, true): self._ownPresence.observer.sendNext(.Online);
                };
            };

        // display status mode icons.
        mainView.hiddenMode.observeNext { on in
            self._hiddenModeIcon.animator().alphaValue = (on ? 1.0 : 0.0);
            self._muteModeIcon.animator().frame.origin = NSPoint(x: self._muteModeIcon.frame.origin.x, y: (on ? self.icon2Y : self.icon1Y));
        };
        mainView.mutedMode.observeNext { on in self._muteModeIcon.animator().alphaValue = (on ? 1.0 : 0.0) }
    }

    private func drawContact(contact: Contact) -> ContactTile {
        let tile = ContactTile(
            frame: NSRect(origin: NSPoint.init(x: 0, y: self.iconMargin), size: self.tileSize),
            contact: contact
        );
        dispatch_async(dispatch_get_main_queue(), {
            self.addSubview(tile);
            self.sendSubviewToBack(tile);
        });
        return tile;
    }
}
