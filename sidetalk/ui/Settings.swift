
import Foundation;
import Cocoa;
import SSKeychain;
import MASShortcut;
import ReactiveCocoa;
import enum Result.NoError;

class SettingsController: NSViewController {
    private var _keyMonitor: AnyObject?;
    private let _testConnection = MutableProperty<Connection?>(nil);

    private let credentialInputDelay = NSTimeInterval(0.5);

    @IBOutlet private var emailField: NSTextField?;
    @IBOutlet private var passwordField: NSTextField?;
    @IBOutlet private var statusImage: NSImageView?;
    @IBOutlet private var shortcutView: MASShortcutView?;

    private var _emailDelegate: STTextDelegate?;
    private var _passwordDelegate: STTextDelegate?;

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
        super.viewDidLoad();

        // if we are trying the connection, show the appropriate status.
        self._testConnection.signal.map({ connection in
            return connection?.connected
                .combineWithDefault(connection!.authenticated, defaultValue: false)
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
                        SSKeychain.setPassword(self.passwordField!.stringValue, forService: "Sidetalk", account: self.emailField!.stringValue);
                        (NSApplication.sharedApplication().delegate as! AppDelegate).connect();
                    }
                };
        }).combinePrevious(nil).observeNext { last, _ in last?.dispose(); };

        // if we already have account information, fill it in.
        if let account = NSUserDefaults.standardUserDefaults().stringForKey("mainAccount") {
            if let field = self.emailField { field.stringValue = account; }
        }

        // hook up our own listeners to the textfields so we get immediate notification.
        let scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "credentials-debouncer");
        if let field = self.emailField {
            self._emailDelegate = STTextDelegate(field: field);
            self._emailDelegate!.text.debounce(self.credentialInputDelay, onScheduler: scheduler).observeNext { _ in self.credentialsChanged(); };
        }
        if let field = self.passwordField {
            self._passwordDelegate = STTextDelegate(field: field);
            self._passwordDelegate!.text.debounce(self.credentialInputDelay, onScheduler: scheduler).observeNext { _ in self.credentialsChanged(); };
        }

        // hook up the shortcut view to the correct prefkey.
        if let field = self.shortcutView { field.associatedUserDefaultsKey = "globalActivation"; }
    }

    private func credentialsChanged() {
        if let email = self.emailField?.stringValue, password = self.passwordField?.stringValue {
            self._testConnection.modify({ last in
                // kill the previous one if we have it.
                if let connection = last { connection.stream.disconnect(); }

                // set up a new one, and have it use our password.
                let connection = Connection();
                connection.connected.observeNext { connected in
                    if connected == true { try! connection.stream.authenticateWithPassword(password); }
                };
                connection.connect(email);
                return connection;
            });
        }
    }

    @IBAction func show2FA(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://security.google.com/settings/security/apppasswords")!);
    }
}
