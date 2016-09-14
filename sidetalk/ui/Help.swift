
import Foundation;
import WebKit;
import MASShortcut;

class HelpController: NSViewController, WebFrameLoadDelegate {
    @IBOutlet private var webView: WebView?;

    override func viewWillAppear() {
        super.viewWillAppear();

        // load up our page in the webview.
        NSLog(NSBundle.mainBundle().pathForResource("help", ofType: "html", inDirectory: "web") ?? "no path");

        if let path = NSBundle.mainBundle().pathForResource("help", ofType: "html", inDirectory: "web"), let webView = self.webView {
            webView.frameLoadDelegate = self;
            webView.mainFrame.loadRequest(NSURLRequest(URL: NSURL.fileURLWithPath(path)));
        }
    }

    func webView(webView: WebView!, didClearWindowObject windowObject: WebScriptObject!, forFrame frame: WebFrame!) {
        // the webview window is ready to receive values; populate it with our current shortcut key.
        let data = NSUserDefaults.standardUserDefaults().dataForKey("globalActivation");
        let shortcut: MASShortcut = (data == nil) ?
            MASShortcut.init(keyCode: 0x31, modifierFlags: NSEventModifierFlags.ControlKeyMask.rawValue) :
            try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data!) as! MASShortcut;
        windowObject.setValue(shortcut.description, forKey: "globalActivation");

        // also populate it with whether the user has an account configured.
        windowObject.setValue(NSUserDefaults.standardUserDefaults().stringForKey("mainAccount"), forKey: "mainAccount");
    }

    @IBAction func done(sender: AnyObject) {
        self.view.window!.close();
    }
}
