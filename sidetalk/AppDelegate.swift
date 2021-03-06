
import Cocoa;
import ReactiveSwift;
import enum Result.NoError;

class MainWindow: NSWindow {
    override var canBecomeKey: Bool { get { return true; } };
    override var canBecomeMain: Bool { get { return true; } };
}

typealias VoidFunction = () -> ();

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {

    @IBOutlet weak var window: MainWindow!;
    let messageLog: MessageLog?;
    let connection: Connection;
    var mainView: MainView?;
    let hiddenJids: Registry;

    @IBOutlet weak var windowMenu: NSMenuItem!;
    @IBOutlet weak var hideMenuItem: NSMenuItem!;
    @IBOutlet weak var muteMenuItem: NSMenuItem!;
    @IBOutlet weak var hiddenContactsMenu: NSMenu!

    private var _settingsController: SettingsController?;
    private var _settingsWindow: NSWindow?;

    private var _helpController: HelpController?;
    private var _helpWindow: NSWindow?;

    private var _otherWindows = Set<NSWindow>();
    private let _underlayWindow = NSWindow();

    private var _notificationActions = [NSUserNotification : VoidFunction]();

    let WIDTH: CGFloat = 400;
    let startup: Date;

    override init() {
        self.hiddenJids = Registry.create(filename: "hidden")!;
        self.messageLog = MessageLog.create();
        self.connection = OAuthConnection(messageLog: self.messageLog);
        self.startup = Date();

        super.init();
        self.connection.fault.observeValues({ fault in self._handleConnectionFault(fault) });
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL), forEventClass: UInt32(kInternetEventClass), andEventID: UInt32(kAEGetURL));
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosing), name: NSWindow.willCloseNotification, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(windowFocusing), name: NSWindow.didBecomeKeyNotification, object: nil);

        // do initial things with window:
        let window = self.window!;
        
        // make our window transparent.
        window.isOpaque = false;
        window.backgroundColor = NSColor.clear;
        window.styleMask = .borderless; //NSBorderlessWindowMask;
        window.hasShadow = false; // shadows are currently causing problems w core animation.
        
        // now set up the underlay window similarly.
        self._underlayWindow.isOpaque = false;
        self._underlayWindow.backgroundColor = NSColor.clear;
        self._underlayWindow.styleMask = .borderless;
        self._underlayWindow.hasShadow = false; // no reason for this simple overlay to have a shadow
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // set up signals.
        self.prepare();

        // do more things with window:
        // ignore mouse events by default.
        self.window!.ignoresMouseEvents = true;

        // position our window.
        let frame = self.positionWindow();

        // quick detour to set up our underlay window:
        self._underlayWindow.ignoresMouseEvents = true;
        self._underlayWindow.setFrame(frame, display: false);
        self._underlayWindow.collectionBehavior = [self._underlayWindow.collectionBehavior, NSWindow.CollectionBehavior.canJoinAllSpaces];
        self._underlayWindow.level = .floating; //CGWindowLevelForKey(.FloatingWindowLevelKey);
        self._underlayWindow.alphaValue = 0;

        // make the underlay blurred view and add it to the window.
        let underlayView = NSVisualEffectView(frame: self._underlayWindow.contentView!.bounds);
        underlayView.blendingMode = .behindWindow;
        underlayView.material = .hudWindow;
        underlayView.state = .active;
        self._underlayWindow.contentView!.addSubview(underlayView);

        // appear on all spaces, and always on top.
        window.collectionBehavior = [window.collectionBehavior, NSWindow.CollectionBehavior.canJoinAllSpaces];
        window.level = .floating; //CGWindowLevelForKey(.FloatingWindowLevelKey);

        // set our primary view.
        self.mainView = MainView(frame: frame, connection: self.connection, underlay: self._underlayWindow,
                                 starred: Registry.create(filename: "starred")!, hidden: self.hiddenJids);
        self.mainView!.frame = window.contentView!.bounds;
        window.contentView!.addSubview(self.mainView!);
        window.makeKeyAndOrderFront(self);

        // now show the underlay window:
        self._underlayWindow.makeKeyAndOrderFront(self);
        self._underlayWindow.order(.below, relativeTo: self.window!.windowNumber);

        // restore hide/mute settings.
        if UserDefaults.standard.bool(forKey: "hidden") == true { self.toggleHidden(self); }
        if UserDefaults.standard.bool(forKey: "muted") == true { self.toggleMuted(self); }

        // attempt to connect.
        if UserDefaults.standard.bool(forKey: "hasRun") != true {
            UserDefaults.standard.set(true, forKey: "hasRun");
            self.showHelp(self);
        } else {
            self.connect();
        }
    }

    // TODO: why does this mutate directly?
    private func positionWindow() -> CGRect {
        let screenFrame = NSScreen.main!.visibleFrame;
        let frame = CGRect(
            x: screenFrame.origin.x + screenFrame.size.width - self.WIDTH, y: 0,
            width: self.WIDTH, height: screenFrame.size.height
        );
        if frame != window.frame { window.setFrame(frame, display: true); }
        return frame;
    }

    func connect() {
        // if we have an account to connect to, do so. otherwise, show the prefpane.
        if let account = UserDefaults.standard.string(forKey: "mainAccount") {
            self.connection.connect(account);
        } else {
            self.showPreferences(self);
        }
    }

    func prepare() {
        self.hiddenJids.members.observeValues({ members in
            DispatchQueue.main.async(execute: { self._updateHiddenContacts(members); });
        });

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApplication.shared, queue: OperationQueue.main) { notification -> Void in
                if let mainView = self.mainView {
                    DispatchQueue.main.async(execute: {
                        self.positionWindow();
                        mainView.frame = self.window.contentView!.bounds;
                    })
                }
        }
    }

    private func _updateHiddenContacts(_ members: Set<String>) {
        self.hiddenContactsMenu.removeAllItems();
        if members.isEmpty {
            let item = NSMenuItem.init(title: "(none)", action: #selector(noop), keyEquivalent: "");
            item.isEnabled = false;
            self.hiddenContactsMenu.addItem(item);
        } else {
            for member in members {
                let item = NSMenuItem.init(title: member, action: #selector(toggleHiddenContact), keyEquivalent: "");
                item.target = self;
                self.hiddenContactsMenu.addItem(item);
            }
        }
    }
    @objc func noop() {}
    @objc func toggleHiddenContact(sender: AnyObject) {
        if let item = sender as? NSMenuItem {
            self.hiddenJids.toggle(item.title);
        }
    }

    private func _handleConnectionFault(_ fault: ConnectionFault) {
        let (headline, detail) = fault.messages();
        let logSnapshot = STMemoryLogger.sharedInstance.all();

        self.showNotification(headline, action: {
            let finalText = NSMutableAttributedString();
            let errorText = NSAttributedString(string: "\(headline).\n\(detail)\n\n", attributes: [ NSAttributedStringKey.font: ST.main.boldFont ]);
            finalText.append(errorText);
            finalText.append(NSAttributedString.init(string: logSnapshot));
            self.showLogs(finalText);
        });
    }

    @IBAction func toggleHidden(_ sender: Any) {
        let hidden = (self.hideMenuItem.state == NSControl.StateValue.off);
        self.mainView!.setHide(hidden);
        UserDefaults.standard.set(hidden, forKey: "hidden");
        self.hideMenuItem.state = hidden ? NSControl.StateValue.on : NSControl.StateValue.off;
    }

    @IBAction func toggleMuted(_ sender: Any) {
        let muted = (self.muteMenuItem.state == NSControl.StateValue.off);
        self.mainView!.setMute(muted);
        UserDefaults.standard.set(muted, forKey: "muted");
        self.muteMenuItem.state = muted ? NSControl.StateValue.on : NSControl.StateValue.off;
    }

    @IBAction func showPreferences(_ sender: Any) {
        if self._settingsWindow == nil {
            self._settingsController = SettingsController(nibName: NSNib.Name(rawValue: "Settings"), bundle: nil);
            self._settingsWindow = NSWindow(contentViewController: self._settingsController!);

            self._settingsWindow!.title = "Sidetalk Preferences";
            self._settingsWindow!.nextResponder = self.window;
        }
        self._settingsWindow!.makeKeyAndOrderFront(nil);
    }

    @IBAction func showHelp(_ sender: Any) {
        if self._helpWindow == nil {
            self._helpController = HelpController(nibName: NSNib.Name(rawValue: "Help"), bundle: nil);
            self._helpWindow = NSWindow(contentViewController: self._helpController!);

            self._helpWindow!.title = "Getting Started";
            self._helpWindow!.nextResponder = self.window;
            self._helpWindow!.minSize = NSSize(width: 700, height: 400);
        }
        self._helpWindow!.makeKeyAndOrderFront(nil);
    }

    @IBAction func showCurrentLogs(_ sender: Any) {
        self.showLogs(NSAttributedString.init(string: STMemoryLogger.sharedInstance.all()));
    }

    func showLogs(_ logs: NSAttributedString) {
        let controller = LogViewerController(nibName: NSNib.Name(rawValue: "LogViewer"), bundle: nil);
        let window = NSWindow(contentViewController: controller);
        window.title = "Log Viewer";
        window.nextResponder = self.window;
        window.minSize = NSSize(width: 600, height: 400);
        window.makeKeyAndOrderFront(nil);

        controller.setText(logs);
        self._otherWindows.insert(window);
    }

    private func showNotification(_ message: String, action: VoidFunction? = .none) {
        let notification = NSUserNotification.init();
        notification.title = "Sidetalk";
        notification.informativeText = message;

        if case let .some(vf) = action {
            notification.actionButtonTitle = "More";
            notification.hasActionButton = true;
            self._notificationActions[notification] = vf;
        }

        let center = NSUserNotificationCenter.default;
        center.delegate = self;
        center.deliver(notification);
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true;
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if let action = self._notificationActions[notification] { action(); }
    }

    @IBAction func closeWindow(_ sender: Any) {
        if let window = NSApp.keyWindow {
            if window != self.window { window.close(); }
        }
    }

    @objc private func windowClosing(notification: NSNotification) {
        if (notification.object as! NSWindow) == self._helpWindow {
            // if we're closing the help screen and no account is configured, show that.
            if UserDefaults.standard.string(forKey: "mainAccount") == nil { self.showPreferences(self); }
        }

        self._otherWindows.remove(notification.object as! NSWindow);
    }

    @objc private func windowFocusing(notification: NSNotification) {
        let window = notification.object as! NSWindow;
        self.windowMenu.isHidden = ((window == self.window) || (window.level.rawValue == 101)); // TODO: why can't i find NSMainMenuWindowLevel defined?
    }

    @objc private func handleURL(event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: UInt32(keyDirectObject))?.stringValue else { return; }
        guard let url = NSURL.init(string: urlString) else { return; }

        if url.scheme == "com.giantacorn.sidetalk" {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "OAuth2AppDidReceiveCallback"), object: url);
        }
    }

    @IBAction func showSupport(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://sidetalk.freshdesk.com")!);
    }

    @IBAction func sendFeedback(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "mailto:feedback@sidetalk.io")!);
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }
}

