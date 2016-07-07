
import Foundation
import Cocoa

class SettingsController: NSViewController {
    @IBAction func show2FA(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://security.google.com/settings/security/apppasswords")!);
    }
}
