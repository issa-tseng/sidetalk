
import Foundation
import ReactiveCocoa
import enum Result.NoError

class SearchIconView: NSView {
    let iconLayer: SearchIconLayer;

    override init(frame: NSRect) {
        self.iconLayer = SearchIconLayer();

        super.init(frame: frame);
        self.wantsLayer = true;
    }

    override func viewWillMoveToSuperview(newSuperview: NSView?) {
        self.iconLayer.frame = NSRect(origin: NSPoint.zero, size: self.frame.size);
        self.layer!.addSublayer(self.iconLayer);
        self.iconLayer.setNeedsDisplay();

        super.viewWillMoveToSuperview(newSuperview);
    }

    required init(coder: NSCoder) { fatalError("fuck you"); }
}

class SearchIconLayer: CALayer {
    override func drawInContext(ctx: CGContext) {
        self.contentsScale = NSScreen.mainScreen()!.backingScaleFactor;

        // prepare avatar
        let iconBounds = CGRect(origin: CGPoint.zero, size: self.frame.size);

        // prepare and clip
        XUIGraphicsPushContext(ctx);
        let nsPath = NSBezierPath();
        nsPath.appendBezierPathWithRoundedRect(iconBounds,
                                               xRadius: self.frame.size.width / 2,
                                               yRadius: self.frame.size.height / 2);
        nsPath.addClip();

        // draw image
        let image = NSImage.init(byReferencingFile: "/Users/cxlt/Code/sidetalk/sidetalk/Resources/search.png")!;
        image.drawInRect(
            iconBounds,
            fromRect: CGRect.init(origin: CGPoint.zero, size: image.size),
            operation: .CompositeSourceOver,
            fraction: 0.98);

        XUIGraphicsPopContext();
    }
}

class StatusTile: NSView {
    internal let connection: Connection;

    private let _searchField: NSTextField;
    private let _searchIcon: SearchIconView;
    private let _presenceIndicator: PresenceIndicator;

    private let _searchLeecher: STTextDelegate;
    var searchText: Signal<String, NoError> { get { return self._searchLeecher.text; } };

    private let _ownPresence: ManagedSignal<Presence>; // TODO: temporary until i unify presence into contact.
    var ownPresence: Signal<Presence, NoError> { get { return self._ownPresence.signal; } };

    let tileSize = NSSize(width: 300, height: 50);
    let searchFrame = NSRect(origin: NSPoint(x: 30, y: 8), size: NSSize(width: 212, height: 30));
    let presenceIndicatorOrigin = NSPoint(x: 250, y: 5);

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

        self._searchIcon = SearchIconView();
        self._searchIcon.frame = NSRect(origin: NSPoint(x: tileSize.width - tileSize.height, y: 0), size: NSSize(width: tileSize.height, height: tileSize.height));
        self._searchIcon.iconLayer.opacity = 0.0;

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

        self.addSubview(self._searchField);
        self.addSubview(self._searchIcon);
        self.addSubview(self._presenceIndicator);
    }

    func prepare(mainState: Signal<MainState, NoError>) {
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
        mainState.combinePrevious(.Inactive).observeNext { (last, this) in
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
    }

    private func drawContact(contact: Contact) -> ContactTile {
        let tile = ContactTile(
            frame: NSRect(origin: NSPoint.zero, size: self.tileSize),
            size: self.tileSize,
            contact: contact
        );
        dispatch_async(dispatch_get_main_queue(), {
            self.addSubview(tile);
            self.sendSubviewToBack(tile);
        });
        return tile;
    }
}
