
import Foundation;
import Cocoa;
import MASShortcut;
import p2_OAuth2;
import ReactiveCocoa;
import enum Result.NoError;

// TODO: the clear button is written old-school instead of rx.

class SettingsController: NSViewController {
    private var _keyMonitor: AnyObject?;
    private let _testConnection = MutableProperty<Connection?>(nil);

    private let _oauth2 = OAuth2CodeGrant(settings: ST.oauth.settings);

    @IBOutlet private var emailLabel: NSTextField?;
    @IBOutlet private var clearAccountButton: NSButton?;
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
                        if let button = self.clearAccountButton { button.hidden = false; }
                    }
                };
        }).combinePrevious(nil).observeNext { last, _ in last?.dispose(); };

        // handle the redirect callback.
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(handleCallback), name: "OAuth2AppDidReceiveCallback", object: nil);

        // if we already have account information, fill it in, light green, and show the x button.
        if let account = NSUserDefaults.standardUserDefaults().stringForKey("mainAccount") {
            if let field = self.emailLabel { field.stringValue = account; }
            if let light = self.statusImage { light.image = NSImage.init(named: NSImageNameStatusAvailable); }
            if let button = self.clearAccountButton { button.hidden = false; }
        }

        // hook up the shortcut view to the correct prefkey.
        if let field = self.shortcutView { field.associatedUserDefaultsKey = "globalActivation"; }
    }

    @IBAction func showAuth(sender: AnyObject) {
        if let light = self.statusImage { light.image = NSImage.init(named: NSImageNameStatusPartiallyAvailable); }

        self._oauth2.verbose = true;
        self._oauth2.onAuthorize = { _ in
            // extract our token.
            guard let password = self._oauth2.accessToken else { return self.fail(nil); }

            // okay, we have a token but (harrumph) no user email. so now go get that.
            let request = self._oauth2.request(forURL: NSURL.init(string: "https://www.googleapis.com/plus/v1/people/me")!);
            self._oauth2.session.dataTaskWithRequest(request, completionHandler: { rawdata, status, error in
                guard let data = rawdata else { return self.fail(nil); }
                guard let rawhead = try? NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()),
                      let head = rawhead as? [String : AnyObject],
                      let emails = (head["emails"] as? [AnyObject]),
                      let primaryEmailInfo = (emails[0] as? [String : AnyObject]),
                      var email = primaryEmailInfo["value"] as? String else { return self.fail(nil); }

                if let match = email.rangeOfString("@gmail\\.com$", options: .RegularExpressionSearch) {
                    // for whatever reason, google refuses to start the stream if i'm connecting with a full
                    // @gmail.com address. works fine with apps domains addresses.
                    email.removeRange(match);
                }

                self._testConnection.modify({ last in
                    // kill the previous one if we have it.
                    if let connection = last { connection.stream.disconnect(); }

                    // set up a new one, and have it use our password.
                    let connection = Connection();
                    connection.connected.observeNext { connected in
                        if connected == true { try! connection.stream.authenticateWithGoogleAccessToken(password); }
                    };
                    connection.authenticated.observeNext { authenticated in
                        if authenticated == true {
                            // it works; make this working account the primary and make it go.
                            NSUserDefaults.standardUserDefaults().setValue(email, forKey: "mainAccount");
                            if let field = self.emailLabel { field.stringValue = email; }

                            // wait a tick for everything to be stored to keychain.
                            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), {
                                (NSApplication.sharedApplication().delegate as! AppDelegate).connect();
                            });
                        }
                    }
                    connection.connect(email);
                    return connection;
                });
            }).resume();
        };
        self._oauth2.authConfig.authorizeEmbedded = false;
        self._oauth2.authorize();
    }

    @IBAction func clearAccount(sender: AnyObject) {
        NSUserDefaults.standardUserDefaults().removeObjectForKey("mainAccount");
        self._oauth2.forgetTokens();

        if let field = self.emailLabel { field.stringValue = ""; }
        if let light = self.statusImage { light.image = NSImage.init(named: NSImageNameStatusNone); }
        if let button = self.clearAccountButton { button.hidden = true; }
    }

    @objc private func handleCallback(notification: NSNotification) {
        if let url = notification.object as? NSURL { self._oauth2.handleRedirectURL(url); }
    }

    private func fail(message: String?) {
        if let light = self.statusImage { light.image = NSImage.init(named: NSImageNameStatusUnavailable); }
        if let field = self.emailLabel { field.stringValue = message ?? "Something went wrong; try again."; }
    }
}
