
import Foundation
import ReactiveCocoa
import enum Result.NoError

class NSTextFieldDelegateProxy: NSObject, NSTextFieldDelegate {
    private let _searchContents = ManagedSignal<String>();
    var searchContentsSignal: Signal<String, NoError> { get { return self._searchContents.signal; } }
    @objc override func controlTextDidChange(obj: NSNotification) {
        let field = obj.userInfo!["NSFieldEditor"] as! NSTextView;
        self._searchContents.observer.sendNext(field.string ?? "");
    }
}

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
        NSLog("actually drawing");

        XUIGraphicsPopContext();
    }
}

class StatusTile: NSView {
    internal let connection: Connection;

    private let _searchField: NSTextField;
    private let _searchIcon: SearchIconView;

    private let _searchDelegateProxy = NSTextFieldDelegateProxy();
    var searchText: Signal<String, NoError> { get { return self._searchDelegateProxy.searchContentsSignal; } };

    let tileSize = NSSize(width: 300, height: 50);
    let searchFrame = NSRect(origin: NSPoint(x: 30, y: 8), size: NSSize(width: 212, height: 30));

    init(connection: Connection, frame: NSRect) {
        self.connection = connection;

        self._searchField = NSTextField(frame: searchFrame);
        self._searchField.backgroundColor = NSColor.clearColor();
        self._searchField.bezeled = false;
        self._searchField.focusRingType = NSFocusRingType.None;
        self._searchField.alignment = NSTextAlignment.Right;
        self._searchField.font = NSFont.systemFontOfSize(20);
        self._searchField.textColor = NSColor.whiteColor();
        self._searchField.alphaValue = 0.0;
        self._searchField.delegate = self._searchDelegateProxy;

        self._searchIcon = SearchIconView();
        self._searchIcon.frame = NSRect(origin: NSPoint(x: tileSize.width - tileSize.height, y: 0), size: NSSize(width: tileSize.height, height: tileSize.height));
        self._searchIcon.iconLayer.opacity = 0.0;

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

        self.prepare();
    }

    private func prepare() {
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

        // focus textfield if activated. clear it if deactivated.
        GlobalInteraction.sharedInstance.activated.observeNext { activated in
            if activated {
                self._searchField.becomeFirstResponder();
            } else {
                self._searchField.stringValue = "";
                self._searchField.alphaValue = 0.0; // TODO/HACK: i don't like that setting stringValue doesn't fire the delegate.
            }
        }

        // show textfield and search icon if there is content.
        self.searchText.observeNext { text in dispatch_async(dispatch_get_main_queue(), {
            let hasContent = text.characters.count > 0;
            self._searchField.alphaValue = hasContent ? 1.0 : 0.0;
            self._searchIcon.iconLayer.opacity = hasContent ? 1.0 : 0.0;
        }); };
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
