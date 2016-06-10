
import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!;
    let connection: Connection;
    var mainView: MainView?;

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

        // reënable basic magick?
        //self.window?.canBecomeKeyWindow = true
        //self.window?.canBecomeMainWindow = true

        // position our window.
        let screenFrame = NSScreen.mainScreen()!.visibleFrame;
        let frame = CGRect(
            x: screenFrame.origin.x + screenFrame.size.width - self.WIDTH, y: 0,
            width: self.WIDTH, height: screenFrame.size.height
        );
        window.setFrame(frame, display: true);

        // appear on all spaces.
        window.collectionBehavior = NSWindowCollectionBehavior.init(rawValue:
            window.collectionBehavior.rawValue | NSWindowCollectionBehavior.CanJoinAllSpaces.rawValue);

        // set our primary view
        self.mainView = MainView(frame: frame, connection: self.connection);
        self.mainView!.frame = window.contentView!.bounds;
        window.contentView!.addSubview(self.mainView!);
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }
}

