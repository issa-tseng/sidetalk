
import Foundation
import MASShortcut
import ReactiveCocoa
import enum Result.NoError

enum Key : Impulsable {
    case up, down, `return`, lineBreak, escape, globalToggle, focus, blur, click, none;

    static func noopValue() -> Key { return .none; }
}

class GlobalInteraction {
    static let sharedInstance = GlobalInteraction();

    fileprivate let keyGenerator = Impulse.generate(Key);
    fileprivate let _keyPress = ManagedSignal<Impulse<Key>>();
    var keyPress: Signal<Impulse<Key>, NoError> { get { return self._keyPress.signal; } };

    fileprivate let anyModifierMask = NSEventModifierFlags.AlternateKeyMask.rawValue | NSEventModifierFlags.control.rawValue;

    init() {
        // we'll want to blur when the space changes, or we lose focus. and activate if the app is activated from the dock.
        NSWorkspace.shared().notificationCenter.addObserver(self,
            selector: #selector(spaceChanged), name: NSNotification.Name.NSWorkspaceActiveSpaceDidChange, object: nil);
        NSWorkspace.shared().notificationCenter.addObserver(self,
            selector: #selector(appDeactivated), name: NSNotification.Name.NSWorkspaceDidDeactivateApplication, object: nil);
        NSWorkspace.shared().notificationCenter.addObserver(self,
            selector: #selector(appActivated), name: NSNotification.Name.NSWorkspaceDidActivateApplication, object: nil);

        // listen to all key events. vend keystroke.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            if event.keyCode == 126 { // up
                self._keyPress.observer.sendNext(self.keyGenerator.create(.up));
            } else if event.keyCode == 125 { // down
                self._keyPress.observer.sendNext(self.keyGenerator.create(.down));
            } else if event.keyCode == 36 { // enter
                if (event.modifierFlags.rawValue & self.anyModifierMask) > 0 {
                    self._keyPress.observer.sendNext(self.keyGenerator.create(.lineBreak));
                } else {
                    self._keyPress.observer.sendNext(self.keyGenerator.create(.return));
                }
            } else if event.keyCode == 53 { // esc
                self._keyPress.observer.sendNext(self.keyGenerator.create(.escape));
            }
            return event;
        });

        // global shortcut.
        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: "globalActivation", toAction: {
            self._keyPress.observer.sendNext(self.keyGenerator.create(.globalToggle));
        });
    }

    deinit {
        NSWorkspace.shared().notificationCenter.removeObserver(self);
    }

    // this is nasty. we can track the most-recently-focused app before sidetalk, but that's ignorant
    // of which space that was on. so we grab the entire window stack and try to activate whatever is just
    // below us. if we can't find that, just give up.
    func relinquish() {
        // get our own application. if there isn't one, don't do anything.
        guard let ownApp = NSWorkspace.shared().frontmostApplication else { return; }

        // nothing to be done if we're already blurred.
        if ownApp.bundleIdentifier != "com.giantacorn.sidetalk" { return; }

        // get the entire stack of currently-visible real windows.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], CGWindowID(0)) else { return; }

        // iterate til we find ourself. then find the next window down and activate that.
        var foundSelf = false;
        for window in windows {
            if !foundSelf && window.object(forKey: kCGWindowOwnerName) as? String == ownApp.localizedName {
                foundSelf = true;
                continue;
            }

            // window layer of 0 is normalspace.
            if foundSelf && (window.object(forKey: kCGWindowLayer) as? Int) == 0 {
                let pid = window.object(forKey: kCGWindowOwnerPID) as! CFNumberRef;
                if let application = NSWorkspace.shared().runningApplications.find({ app in Int(app.processIdentifier) == Int(pid) }) {
                    application.activate(options: NSApplicationActivationOptions.activateIgnoringOtherApps);
                    return;
                }
            }
        }
    }

    // HACK: i don't like that this is just sort of sitting around.
    func send(_ key: Key) { self._keyPress.observer.sendNext(self.keyGenerator.create(key)); }

    @objc internal func spaceChanged(_ notification: Notification) {
        self._keyPress.observer.sendNext(self.keyGenerator.create(.blur));
    }

    @objc internal func appDeactivated(_ notification: Notification) {
        guard let app = (notification as NSNotification).userInfo?[NSWorkspaceApplicationKey] as? NSRunningApplication else { return; };
        if app.bundleIdentifier == "com.giantacorn.sidetalk" {
            self._keyPress.observer.sendNext(self.keyGenerator.create(.blur));
        }
    }

    @objc internal func appActivated(_ notification: Notification) {
        guard let app = (notification as NSNotification).userInfo?[NSWorkspaceApplicationKey] as? NSRunningApplication else { return; };
        if app.bundleIdentifier == "com.giantacorn.sidetalk" {
            self._keyPress.observer.sendNext(self.keyGenerator.create(.focus));
        }
    }
}
