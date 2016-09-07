
import Foundation
import WebKit

class HelpController: NSViewController {
    @IBOutlet private var webView: WebView?;

    override func viewWillAppear() {
        super.viewWillAppear();

        // load up our page in the webview.
        NSLog(NSBundle.mainBundle().pathForResource("help", ofType: "html", inDirectory: "web") ?? "no path");

        if let path = NSBundle.mainBundle().pathForResource("help", ofType: "html", inDirectory: "web"), let webView = self.webView {
            webView.mainFrame.loadRequest(NSURLRequest(URL: NSURL.fileURLWithPath(path)));
        }
    }

    @IBAction func done(sender: AnyObject) {
        self.view.window!.close();
    }
}
