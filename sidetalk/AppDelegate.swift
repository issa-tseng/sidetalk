
import Cocoa;
import ReactiveCocoa;
import enum Result.NoError;

class MainWindow: NSWindow {
    override var canBecomeKeyWindow: Bool { get { return true; } };
    override var canBecomeMainWindow: Bool { get { return true; } };
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: MainWindow!;
    let connection: Connection;
    var mainView: MainView?;

    private let _settingsShown = MutableProperty<Bool>(false);
    var settingsShown: Signal<Bool, NoError> { get { return self._settingsShown.signal; } };

    private var _settingsController: SettingsController?;
    private var _settingsWindow: NSWindow?;

    private var _helpController: HelpController?;
    private var _helpWindow: NSWindow?;

    let WIDTH: CGFloat = 400;

    override init() {
        self.connection = DemoConnection();
        super.init();
    }

    func applicationWillFinishLaunching(notification: NSNotification) {
        NSAppleEventManager.sharedAppleEventManager().setEventHandler(self, andSelector: #selector(handleURL), forEventClass: UInt32(kInternetEventClass), andEventID: UInt32(kAEGetURL));
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(windowClosing), name: NSWindowWillCloseNotification, object: nil);
    }

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        let window = self.window!

        // make our window transparent.
        window.opaque = false;
        window.backgroundColor = NSColor.clearColor();
        window.styleMask = NSBorderlessWindowMask;

        // shadows are currently causing problems w core animation.
        window.hasShadow = false;

        // ignore mouse events by default.
        self.window!.ignoresMouseEvents = true;

        // position our window.
        let screenFrame = NSScreen.mainScreen()!.visibleFrame;
        let frame = CGRect(
            x: screenFrame.origin.x + screenFrame.size.width - self.WIDTH, y: 0,
            width: self.WIDTH, height: screenFrame.size.height
        );
        window.setFrame(frame, display: true);

        // appear on all spaces, and always on top.
        window.collectionBehavior = [window.collectionBehavior, NSWindowCollectionBehavior.CanJoinAllSpaces];
        window.level = Int(CGWindowLevelForKey(.FloatingWindowLevelKey));

        // set our primary view.
        self.mainView = MainView(frame: frame, connection: self.connection);
        self.mainView!.frame = window.contentView!.bounds;
        window.contentView!.addSubview(self.mainView!);

        // attempt to connect.
        if NSUserDefaults.standardUserDefaults().boolForKey("hasRun") != true {
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: "hasRun");
            self.showHelp(0);
        } else {
            self.connect();
        }
    }

    func connect() {
        // if we have an account to connect to, do so. otherwise, show the prefpane.
        if let account = NSUserDefaults.standardUserDefaults().stringForKey("mainAccount") {
            self.connection.connect(account);
        } else {
            self.showPreferences(0);
        }
    }

    @IBAction func toggleHidden(sender: AnyObject) {
        let item = sender as! NSMenuItem;

        let hidden = (item.state == NSOffState);
        self.mainView!.setHide(hidden);
        item.state = hidden ? NSOnState : NSOffState;
    }

    @IBAction func toggleMuted(sender: AnyObject) {
        let item = sender as! NSMenuItem;

        let muted = (item.state == NSOffState);
        self.mainView!.setMute(muted);
        item.state = muted ? NSOnState : NSOffState;
    }

    @IBAction func showPreferences(sender: AnyObject) {
        if self._settingsWindow == nil {
            self._settingsController = SettingsController(nibName: "Settings", bundle: nil)!;
            self._settingsWindow = NSWindow(contentViewController: self._settingsController!);

            self._settingsWindow!.title = "Sidetalk Preferences";
            self._settingsWindow!.nextResponder = self.window;
        }
        self._settingsWindow!.makeKeyAndOrderFront(nil);
        self._settingsShown.modify { _ in true };
    }

    @IBAction func showHelp(sender: AnyObject) {
        if self._helpWindow == nil {
            self._helpController = HelpController(nibName: "Help", bundle: nil)!;
            self._helpWindow = NSWindow(contentViewController: self._helpController!);

            self._helpWindow!.title = "Getting Started";
            self._helpWindow!.nextResponder = self.window;
            self._helpWindow!.minSize = NSSize(width: 700, height: 400);
        }
        self._helpWindow!.makeKeyAndOrderFront(nil);
    }

    @objc private func windowClosing(notification: NSNotification) {
        if (notification.object as! NSWindow) == self._settingsWindow { self._settingsShown.modify { _ in false }; }

        if (notification.object as! NSWindow) == self._helpWindow {
            // if we're closing the help screen and no account is configured, show that.
            if NSUserDefaults.standardUserDefaults().stringForKey("mainAccount") == nil { self.showPreferences(0); }
        }
    }

    @objc private func handleURL(event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptorForKeyword(UInt32(keyDirectObject))?.stringValue else { return; }
        guard let url = NSURL.init(string: urlString) else { return; }

        if url.scheme == "com.giantacorn.sidetalk" {
            NSNotificationCenter.defaultCenter().postNotificationName("OAuth2AppDidReceiveCallback", object: url);
        }
    }

    @IBAction func showSupport(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://sidetalk.freshdesk.com")!);
    }

    @IBAction func sendFeedback(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "mailto:feedback@sidetalk.io")!);
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }
}

