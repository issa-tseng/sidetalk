
import Foundation;
import Cocoa;
import SSKeychain;

class SettingsController: NSViewController {
    private var _keyMonitor: AnyObject?;
    private let _testConnection = Connection();

    @IBOutlet private var emailField: NSTextField?;
    @IBOutlet private var passwordField: NSTextField?;
    @IBOutlet private var statusImage: NSImageView?;

    override func viewWillAppear() {
        // wire up cmd+w the manual way.
        self._keyMonitor = NSEvent.addLocalMonitorForEventsMatchingMask(.KeyDownMask, handler: { event in
            if event.keyCode == 13 && event.modifierFlags.contains(NSEventModifierFlags.CommandKeyMask) {
                self.view.window!.close();
                NSEvent.removeMonitor(self._keyMonitor!);
                return nil;
            }
            return event;
        });

        super.viewWillAppear();
    }

    private enum TestResult { case None, Pending, Failed, Succeeded; }
    override func viewDidLoad() {
        // if we are trying the connection, show the appropriate status.
        self._testConnection.connected
            .combineWithDefault(self._testConnection.authenticated, defaultValue: false)
            .scan(.None, { (last, args) -> TestResult in
                let (connected, authenticated) = args;
                switch (last, connected, authenticated) {
                case (_, true, false): return .Pending;
                case (_, true, true): return .Succeeded;
                case (.Pending, false, false): return .Failed;
                default: return last;
                }
            }).observeNext { result in
                if result == .None {
                    self.statusImage!.image = NSImage.init(named: NSImageNameStatusNone);
                } else if result == .Pending {
                    self.statusImage!.image = NSImage.init(named: NSImageNameStatusPartiallyAvailable);
                } else if result == .Failed {
                    self.statusImage!.image = NSImage.init(named: NSImageNameStatusUnavailable);
                } else if result == .Succeeded {
                    self.statusImage!.image = NSImage.init(named: NSImageNameStatusAvailable);

                    // in addition to setting the status light, make this working account the primary and make it go.
                    NSUserDefaults.standardUserDefaults().setValue(self.emailField!.stringValue, forKey: "mainAccount");
                    (NSApplication.sharedApplication().delegate as! AppDelegate).connect();
                }
            };

        super.viewDidLoad();
    }

    @IBAction func credentialsChanged(sender: AnyObject) {
        if self.emailField!.stringValue != "" && self.passwordField!.stringValue != "" {
            SSKeychain.setPassword(self.passwordField!.stringValue, forService: "Sidetalk", account: self.emailField!.stringValue);
            self._testConnection.connect(self.emailField!.stringValue);
        }
    }

    @IBAction func show2FA(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://security.google.com/settings/security/apppasswords")!);
    }
}
