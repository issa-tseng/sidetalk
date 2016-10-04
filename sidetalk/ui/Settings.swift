
import Foundation;
import Cocoa;
import MASShortcut;
import p2_OAuth2;
import ReactiveCocoa;
import enum Result.NoError;

// TODO: the clear button is written old-school instead of rx.

class SettingsController: NSViewController {
    fileprivate var _keyMonitor: AnyObject?;
    fileprivate let _testConnection = MutableProperty<Connection?>(nil);

    fileprivate let _oauth2 = OAuth2CodeGrant(settings: ST.oauth.settings);

    @IBOutlet fileprivate var emailLabel: NSTextField?;
    @IBOutlet fileprivate var clearAccountButton: NSButton?;
    @IBOutlet fileprivate var statusImage: NSImageView?;
    @IBOutlet fileprivate var shortcutView: MASShortcutView?;

    fileprivate var _emailDelegate: STTextDelegate?;
    fileprivate var _passwordDelegate: STTextDelegate?;

    override func viewWillAppear() {
        // wire up cmd+w the manual way.
        self._keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            if event.keyCode == 13 && event.modifierFlags.contains(NSEventModifierFlags.command) {
                self.view.window!.close();
                NSEvent.removeMonitor(self._keyMonitor!);
                return nil;
            }
            return event;
        }) as AnyObject?;

        super.viewWillAppear();
    }

    fileprivate enum TestResult { case none, pending, failed, succeeded; }
    override func viewDidLoad() {
        super.viewDidLoad();

        // if we are trying the connection, show the appropriate status.
        self._testConnection.signal.map({ connection in
            return connection?.connected
                .combineWithDefault(connection!.authenticated, defaultValue: false)
                .scan(.none, { (last, args) -> TestResult in
                    let (connected, authenticated) = args;
                    switch (last, connected, authenticated) {
                    case (_, true, false): return .pending;
                    case (_, true, true): return .succeeded;
                    case (.pending, false, false): return .failed;
                    default: return last;
                    }
                }).observeNext { result in
                    if result == .none {
                        self.statusImage!.image = NSImage.init(named: NSImageNameStatusNone);
                    } else if result == .pending {
                        self.statusImage!.image = NSImage.init(named: NSImageNameStatusPartiallyAvailable);
                    } else if result == .failed {
                        self.statusImage!.image = NSImage.init(named: NSImageNameStatusUnavailable);
                    } else if result == .succeeded {
                        self.statusImage!.image = NSImage.init(named: NSImageNameStatusAvailable);
                        if let button = self.clearAccountButton { button.isHidden = false; }
                    }
                };
        }).combinePrevious(nil).observeNext { last, _ in last?.dispose(); };

        // handle the redirect callback.
        NotificationCenter.default.addObserver(self, selector: #selector(handleCallback), name: NSNotification.Name(rawValue: "OAuth2AppDidReceiveCallback"), object: nil);

        // if we already have account information, fill it in, light green, and show the x button.
        if let account = UserDefaults.standard.string(forKey: "mainAccount") {
            if let field = self.emailLabel { field.stringValue = account; }
            if let light = self.statusImage { light.image = NSImage.init(named: NSImageNameStatusAvailable); }
            if let button = self.clearAccountButton { button.isHidden = false; }
        }

        // hook up the shortcut view to the correct prefkey.
        if let field = self.shortcutView { field.associatedUserDefaultsKey = "globalActivation"; }
    }

    @IBAction func showAuth(_ sender: AnyObject) {
        if let light = self.statusImage { light.image = NSImage.init(named: NSImageNameStatusPartiallyAvailable); }

        self._oauth2.verbose = true;
        self._oauth2.onAuthorize = { _ in
            // extract our token.
            guard let password = self._oauth2.accessToken else { return self.fail(nil); }

            // okay, we have a token but (harrumph) no user email. so now go get that.
            let request = self._oauth2.request(forURL: URL.init(string: "https://www.googleapis.com/plus/v1/people/me")!);
            self._oauth2.session.dataTask(with: request, completionHandler: { rawdata, status, error in
                guard let data = rawdata else { return self.fail(nil); }
                guard let rawhead = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions()),
                      let head = rawhead as? [String : AnyObject],
                      let emails = (head["emails"] as? [AnyObject]),
                      let primaryEmailInfo = (emails[0] as? [String : AnyObject]),
                      var email = primaryEmailInfo["value"] as? String else { return self.fail(nil); }

                if let match = email.range(of: "@gmail\\.com$", options: .regularExpression) {
                    // for whatever reason, google refuses to start the stream if i'm connecting with a full
                    // @gmail.com address. works fine with apps domains addresses.
                    email.removeSubrange(match);
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
                            UserDefaults.standard.setValue(email, forKey: "mainAccount");
                            if let field = self.emailLabel { field.stringValue = email; }

                            // wait a tick for everything to be stored to keychain.
                            DispatchQueue.global(qos: DispatchQoS.QoSClass.default).async(execute: {
                                (NSApplication.shared().delegate as! AppDelegate).connect();
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

    @IBAction func clearAccount(_ sender: AnyObject) {
        UserDefaults.standard.removeObject(forKey: "mainAccount");
        self._oauth2.forgetTokens();

        if let field = self.emailLabel { field.stringValue = ""; }
        if let light = self.statusImage { light.image = NSImage.init(named: NSImageNameStatusNone); }
        if let button = self.clearAccountButton { button.isHidden = true; }
    }

    @objc fileprivate func handleCallback(_ notification: Notification) {
        if let url = notification.object as? URL { self._oauth2.handleRedirectURL(url); }
    }

    fileprivate func fail(_ message: String?) {
        if let light = self.statusImage { light.image = NSImage.init(named: NSImageNameStatusUnavailable); }
        if let field = self.emailLabel { field.stringValue = message ?? "Something went wrong; try again."; }
    }
}
