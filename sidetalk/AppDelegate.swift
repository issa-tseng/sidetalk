
import Cocoa;
import ReactiveCocoa;
import enum Result.NoError;

class MainWindow: NSWindow {
    override var canBecomeKey: Bool { get { return true; } };
    override var canBecomeMain: Bool { get { return true; } };
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: MainWindow!;
    let connection: Connection;
    var mainView: MainView?;

    fileprivate let _settingsShown = MutableProperty<Bool>(false);
    var settingsShown: Signal<Bool, NoError> { get { return self._settingsShown.signal; } };

    fileprivate var _settingsController: SettingsController?;
    fileprivate var _settingsWindow: NSWindow?;

    fileprivate var _helpController: HelpController?;
    fileprivate var _helpWindow: NSWindow?;

    let WIDTH: CGFloat = 400;

    override init() {
        self.connection = OAuthConnection();
        super.init();
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL), forEventClass: UInt32(kInternetEventClass), andEventID: UInt32(kAEGetURL));
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosing), name: NSNotification.Name.NSWindowWillClose, object: nil);
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let window = self.window!

        // make our window transparent.
        window.isOpaque = false;
        window.backgroundColor = NSColor.clear;
        window.styleMask = NSBorderlessWindowMask;

        // shadows are currently causing problems w core animation.
        window.hasShadow = false;

        // ignore mouse events by default.
        self.window!.ignoresMouseEvents = true;

        // position our window.
        let screenFrame = NSScreen.main()!.visibleFrame;
        let frame = CGRect(
            x: screenFrame.origin.x + screenFrame.size.width - self.WIDTH, y: 0,
            width: self.WIDTH, height: screenFrame.size.height
        );
        window.setFrame(frame, display: true);

        // appear on all spaces, and always on top.
        window.collectionBehavior = [window.collectionBehavior, NSWindowCollectionBehavior.canJoinAllSpaces];
        window.level = Int(CGWindowLevelForKey(.floatingWindow));

        // set our primary view.
        self.mainView = MainView(frame: frame, connection: self.connection);
        self.mainView!.frame = window.contentView!.bounds;
        window.contentView!.addSubview(self.mainView!);

        // attempt to connect.
        if UserDefaults.standard.bool(forKey: "hasRun") != true {
            UserDefaults.standard.set(true, forKey: "hasRun");
            self.showHelp(0 as AnyObject);
        } else {
            self.connect();
        }
    }

    func connect() {
        // if we have an account to connect to, do so. otherwise, show the prefpane.
        if let account = UserDefaults.standard.string(forKey: "mainAccount") {
            self.connection.connect(account);
        } else {
            self.showPreferences(0 as AnyObject);
        }
    }

    @IBAction func toggleHidden(_ sender: AnyObject) {
        let item = sender as! NSMenuItem;

        let hidden = (item.state == NSOffState);
        self.mainView!.setHide(hidden);
        item.state = hidden ? NSOnState : NSOffState;
    }

    @IBAction func toggleMuted(_ sender: AnyObject) {
        let item = sender as! NSMenuItem;

        let muted = (item.state == NSOffState);
        self.mainView!.setMute(muted);
        item.state = muted ? NSOnState : NSOffState;
    }

    @IBAction func showPreferences(_ sender: AnyObject) {
        if self._settingsWindow == nil {
            self._settingsController = SettingsController(nibName: "Settings", bundle: nil)!;
            self._settingsWindow = NSWindow(contentViewController: self._settingsController!);

            self._settingsWindow!.title = "Sidetalk Preferences";
            self._settingsWindow!.nextResponder = self.window;
        }
        self._settingsWindow!.makeKeyAndOrderFront(nil);
        self._settingsShown.modify { _ in true };
    }

    @IBAction func showHelp(_ sender: AnyObject) {
        if self._helpWindow == nil {
            self._helpController = HelpController(nibName: "Help", bundle: nil)!;
            self._helpWindow = NSWindow(contentViewController: self._helpController!);

            self._helpWindow!.title = "Getting Started";
            self._helpWindow!.nextResponder = self.window;
            self._helpWindow!.minSize = NSSize(width: 700, height: 400);
        }
        self._helpWindow!.makeKeyAndOrderFront(nil);
    }

    @objc fileprivate func windowClosing(_ notification: Notification) {
        if (notification.object as! NSWindow) == self._settingsWindow { self._settingsShown.modify { _ in false }; }

        if (notification.object as! NSWindow) == self._helpWindow {
            // if we're closing the help screen and no account is configured, show that.
            if UserDefaults.standard.string(forKey: "mainAccount") == nil { self.showPreferences(0 as AnyObject); }
        }
    }

    @objc fileprivate func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: UInt32(keyDirectObject))?.stringValue else { return; }
        guard let url = URL.init(string: urlString) else { return; }

        if url.scheme == "com.giantacorn.sidetalk" {
            NotificationCenter.default.post(name: Notification.Name(rawValue: "OAuth2AppDidReceiveCallback"), object: url);
        }
    }

    @IBAction func showSupport(_ sender: AnyObject) {
        NSWorkspace.shared().open(URL(string: "https://sidetalk.freshdesk.com")!);
    }

    @IBAction func sendFeedback(_ sender: AnyObject) {
        NSWorkspace.shared().open(URL(string: "mailto:feedback@sidetalk.io")!);
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

