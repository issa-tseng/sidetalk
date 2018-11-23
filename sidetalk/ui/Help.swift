
import Foundation;
import WebKit;
import MASShortcut;

class HelpController: NSViewController {
    override func viewWillAppear() {
        super.viewWillAppear();

        guard let path = Bundle.main.path(forResource: "help", ofType: "html", inDirectory: "web") else { return; }

        // get shortcut/account information:
        let shortcutData = UserDefaults.standard.data(forKey: "globalActivation");
        let shortcut: MASShortcut = (shortcutData == nil) ?
            MASShortcut.init(keyCode: 0x31, modifierFlags: NSEvent.ModifierFlags.control.rawValue) :
            try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(shortcutData!) as! MASShortcut;
        let account = UserDefaults.standard.string(forKey: "mainAccount");

        // formulate data injection script, controller, config object:
        let inject = "window.globalActivation = '\(shortcut.description)'; window.mainAccount = '\(account ?? "")'";
        let script = WKUserScript(source: inject, injectionTime: .atDocumentStart, forMainFrameOnly: true);
        let controller = WKUserContentController();
        controller.addUserScript(script);
        let wkConfig = WKWebViewConfiguration();
        wkConfig.userContentController = controller;
        
        // create a wkwebview and position it (because you can't use IB to set your webview if you want config for some dumb reason)
        let webView = WKWebView(frame: .zero, configuration: wkConfig);
        webView.translatesAutoresizingMaskIntoConstraints = false;
        self.view.addSubview(webView);
        self.view.addConstraints([
            webView.constrain.left == self.view.constrain.left,
            webView.constrain.top == self.view.constrain.top,
            webView.constrain.right == self.view.constrain.right,
            webView.constrain.bottom == self.view.constrain.bottom - 36
        ]);
        webView.load(URLRequest(url: URL(fileURLWithPath: path)));
    }

    @IBAction func done(_ sender: Any) {
        self.view.window!.close();
    }
}
