
import Foundation;
import WebKit;
import MASShortcut;

class HelpController: NSViewController, WebFrameLoadDelegate {
    @IBOutlet private var webView: WebView?;

    override func viewWillAppear() {
        super.viewWillAppear();

        // load up our page in the webview.
        NSLog(Bundle.main.path(forResource: "help", ofType: "html", inDirectory: "web") ?? "no path");

        if let path = Bundle.main.path(forResource: "help", ofType: "html", inDirectory: "web"), let webView = self.webView {
            webView.frameLoadDelegate = self;
            webView.mainFrame.load(URLRequest(url: URL(fileURLWithPath: path)));
        }
    }

    func webView(_ webView: WebView!, didClearWindowObject windowObject: WebScriptObject!, for frame: WebFrame!) {
        // the webview window is ready to receive values; populate it with our current shortcut key.
        let data = UserDefaults.standard.data(forKey: "globalActivation");
        let shortcut: MASShortcut = (data == nil) ?
            MASShortcut.init(keyCode: 0x31, modifierFlags: NSEvent.ModifierFlags.control.rawValue) :
            try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data!) as! MASShortcut;
        windowObject.setValue(shortcut.description, forKey: "globalActivation");

        // also populate it with whether the user has an account configured.
        windowObject.setValue(UserDefaults.standard.string(forKey: "mainAccount"), forKey: "mainAccount");
    }

    @IBAction func done(sender: AnyObject) {
        self.view.window!.close();
    }
}
