
import Foundation;
import Cocoa;
import MASShortcut;
import p2_OAuth2;
import ReactiveSwift;
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
                }).observeValues { result in
                    if result == .None {
                        self.statusImage!.image = NSImage.init(named: NSImage.Name.statusNone);
                    } else if result == .Pending {
                        self.statusImage!.image = NSImage.init(named: NSImage.Name.statusPartiallyAvailable);
                    } else if result == .Failed {
                        self.statusImage!.image = NSImage.init(named: NSImage.Name.statusUnavailable);
                    } else if result == .Succeeded {
                        self.statusImage!.image = NSImage.init(named: NSImage.Name.statusAvailable);
                        if let button = self.clearAccountButton { button.isHidden = false; }
                    }
                };
        }).combinePrevious(nil).observeValues { last, _ in last?.dispose(); };

        // handle the redirect callback.
        NotificationCenter.default.addObserver(self, selector: #selector(handleCallback), name: NSNotification.Name(rawValue: "OAuth2AppDidReceiveCallback"), object: nil);

        // if we already have account information, fill it in, light green, and show the x button.
        if let account = UserDefaults.standard.string(forKey: "mainAccount") {
            if let field = self.emailLabel { field.stringValue = account; }
            if let light = self.statusImage { light.image = NSImage.init(named: NSImage.Name.statusAvailable); }
            if let button = self.clearAccountButton { button.isHidden = false; }
        }

        // hook up the shortcut view to the correct prefkey.
        if let field = self.shortcutView { field.associatedUserDefaultsKey = "globalActivation"; }
    }

    @IBAction func showAuth(sender: AnyObject) {
        if let light = self.statusImage { light.image = NSImage.init(named: NSImage.Name.statusPartiallyAvailable); }

        self._oauth2.verbose = true;
        self._oauth2.authConfig.authorizeEmbedded = false;
        self._oauth2.authorize(callback: { _, _ in
            // extract our token.
            guard let password = self._oauth2.accessToken else { return self.fail(nil); }
            
            // okay, we have a token but (harrumph) no user email. so now go get that.
            let request = self._oauth2.request(forURL: URL.init(string: "https://www.googleapis.com/plus/v1/people/me")!);
            self._oauth2.session.dataTask(with: request, completionHandler: { rawdata, status, error in
                guard let data = rawdata else { return self.fail(nil); }
                guard let rawhead = try? JSONSerialization.jsonObject(with: data),
                    let head = rawhead as? [String : AnyObject],
                    let emails = (head["emails"] as? [AnyObject]),
                    let primaryEmailInfo = (emails[0] as? [String : AnyObject]),
                    var email = primaryEmailInfo["value"] as? String else { return self.fail(nil); }
                
                if let match = email.range(of: "@gmail\\.com$", options: .regularExpression) {
                    // for whatever reason, google refuses to start the stream if i'm connecting with a full
                    // @gmail.com address. works fine with apps domains addresses.
                    email.removeSubrange(match);
                }
                
                self._testConnection.modify({ last -> Connection in
                    // kill the previous one if we have it.
                    if let connection = last { connection.stream.disconnect(); }
                    
                    // set up a new one, and have it use our password.
                    let connection = Connection();
                    connection.fault.observeValues { fault in
                        self._handleConnectionFault(fault);
                    };
                    connection.connected.observeValues { connected in
                        if connected == true { try! connection.stream.authenticate(withGoogleAccessToken: password); }
                    };
                    connection.authenticated.observeValues { authenticated in
                        if authenticated == true {
                            // it works; make this working account the primary and make it go.
                            UserDefaults.standard.setValue(email, forKey: "mainAccount");
                            if let field = self.emailLabel { field.stringValue = email; }
                            
                            // wait a tick for everything to be stored to keychain.
                            DispatchQueue.global(qos: .default).async(execute: {
                                (NSApplication.shared.delegate as! AppDelegate).connect();
                            });
                        }
                    }
                    connection.connect(email);
                    return connection;
                });
            }).resume();
        });
    }

    @IBAction func clearAccount(sender: AnyObject) {
        UserDefaults.standard.removeObject(forKey: "mainAccount");
        self._oauth2.forgetTokens();

        if let field = self.emailLabel { field.stringValue = ""; }
        if let light = self.statusImage { light.image = NSImage.init(named: NSImage.Name.statusNone); }
        if let button = self.clearAccountButton { button.isHidden = true; }
    }

    @objc private func handleCallback(notification: NSNotification) {
        if let url = notification.object as? URL { self._oauth2.handleRedirectURL(url); }
    }

    private func _handleConnectionFault(_ fault: ConnectionFault) {
        let (headline, detail) = fault.messages();

        if let window = self.view.window {
            DispatchQueue.main.async(execute: {
                let alert = NSAlert();

                alert.messageText = headline;
                alert.informativeText = detail;
                alert.beginSheetModal(for: window, completionHandler: { response in });
            });
        }
    }

    private func fail(_ message: String?) {
        if let light = self.statusImage { light.image = NSImage.init(named: NSImage.Name.statusUnavailable); }
        if let field = self.emailLabel { field.stringValue = message ?? "Something went wrong; try again."; }
    }
}
