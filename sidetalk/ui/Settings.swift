
import Foundation
import Cocoa

class SettingsController: NSViewController {
    private var _keyMonitor: AnyObject?;

    override func viewWillAppear() {
        self._keyMonitor = NSEvent.addLocalMonitorForEventsMatchingMask(.KeyDownMask, handler: { event in
            if event.keyCode == 13 && event.modifierFlags.contains(NSEventModifierFlags.CommandKeyMask) {
                self.view.window!.close();
                NSEvent.removeMonitor(self._keyMonitor!);
                return nil;
            }
            return event;
        });
    }

    @IBAction func show2FA(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://security.google.com/settings/security/apppasswords")!);
    }
}
