
import Cocoa

class MainWindow: NSWindow {
    override var canBecomeKeyWindow: Bool { get { return true; } };
    override var canBecomeMainWindow: Bool { get { return true; } };
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: MainWindow!;
    let connection: Connection;
    var mainView: MainView?;

    private var _settingsController: SettingsController?;
    private var _settingsWindow: NSWindow?;

    let WIDTH: CGFloat = 400;

    override init() {
        self.connection = Connection();
        super.init();
    }

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        let window = self.window!

        // make our window transparent.
        window.opaque = false;
        window.backgroundColor = NSColor.clearColor();
        window.styleMask = NSBorderlessWindowMask;

        // shadows are currently causing problems w core animation.
        window.hasShadow = false;

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

            self._settingsWindow!.nextResponder = self.window;
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(blurPreferences), name: NSWindowWillCloseNotification, object: nil);
        }
        self._settingsWindow!.makeKeyAndOrderFront(nil);
    }

    @objc private func blurPreferences(notification: NSNotification) {
        if (notification.object as! NSWindow) == self._settingsWindow {
            self._settingsWindow!.orderOut(nil);
            self.window.makeKeyAndOrderFront(nil);
        }
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }
}

