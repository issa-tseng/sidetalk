
import Foundation
import MASShortcut
import ReactiveCocoa
import enum Result.NoError

enum Key: Impulsable {
    case Up, Down, Return, LineBreak, Escape, GlobalToggle, Focus, Blur, Click, None;

    static func noopValue() -> Key { return .None; }
}

class GlobalInteraction {
    static let sharedInstance = GlobalInteraction();

    private let keyGenerator = Impulse.generate(Key);
    private let _keyPress = ManagedSignal<Impulse<Key>>();
    var keyPress: Signal<Impulse<Key>, NoError> { get { return self._keyPress.signal; } };

    private let anyModifierMask = NSEventModifierFlags.Option.rawValue | NSEventModifierFlags.Control.rawValue;

    init() {
        // we'll want to blur when the space changes, or we lose focus. and activate if the app is activated from the dock.
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(self,
            selector: #selector(spaceChanged), name: NSWorkspaceActiveSpaceDidChangeNotification, object: nil);
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(self,
            selector: #selector(appDeactivated), name: NSWorkspaceDidDeactivateApplicationNotification, object: nil);
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(self,
            selector: #selector(appActivated), name: NSWorkspaceDidActivateApplicationNotification, object: nil);

        // listen to all key events. vend keystroke.
        NSEvent.addLocalMonitorForEventsMatchingMask(.KeyDown, handler: { event in
            if event.keyCode == 126 { // up
                self._keyPress.observer.sendNext(self.keyGenerator.create(.Up));
            } else if event.keyCode == 125 { // down
                self._keyPress.observer.sendNext(self.keyGenerator.create(.Down));
            } else if event.keyCode == 36 { // enter
                if (event.modifierFlags.rawValue & self.anyModifierMask) > 0 {
                    self._keyPress.observer.sendNext(self.keyGenerator.create(.LineBreak));
                } else {
                    self._keyPress.observer.sendNext(self.keyGenerator.create(.Return));
                }
            } else if event.keyCode == 53 { // esc
                self._keyPress.observer.sendNext(self.keyGenerator.create(.Escape));
            }
            return event;
        });

        // global shortcut.
        MASShortcutBinder.sharedBinder().bindShortcutWithDefaultsKey("globalActivation", toAction: {
            self._keyPress.observer.sendNext(self.keyGenerator.create(.GlobalToggle));
        });
    }

    deinit {
        NSWorkspace.sharedWorkspace().notificationCenter.removeObserver(self);
    }

    // this is nasty. we can track the most-recently-focused app before sidetalk, but that's ignorant
    // of which space that was on. so we grab the entire window stack and try to activate whatever is just
    // below us. if we can't find that, just give up.
    func relinquish() {
        // get our own application. if there isn't one, don't do anything.
        guard let ownApp = NSWorkspace.sharedWorkspace().frontmostApplication else { return; }

        // nothing to be done if we're already blurred.
        if ownApp.bundleIdentifier != "com.giantacorn.sidetalk" { return; }

        // get the entire stack of currently-visible real windows.
        guard let windows = CGWindowListCopyWindowInfo([.OptionOnScreenOnly, .ExcludeDesktopElements], CGWindowID(0)) else { return; }

        // iterate til we find ourself. then find the next window down and activate that.
        var foundSelf = false;
        for window in windows {
            if !foundSelf && window.objectForKey(kCGWindowOwnerName) as? String == ownApp.localizedName {
                foundSelf = true;
                continue;
            }

            // window layer of 0 is normalspace.
            if foundSelf && (window.objectForKey(kCGWindowLayer) as? Int) == 0 {
                let pid = window.objectForKey(kCGWindowOwnerPID) as! CFNumberRef;
                if let application = NSWorkspace.sharedWorkspace().runningApplications.find({ app in Int(app.processIdentifier) == Int(pid) }) {
                    application.activateWithOptions(NSApplicationActivationOptions.ActivateIgnoringOtherApps);
                    return;
                }
            }
        }
    }

    // HACK: i don't like that this is just sort of sitting around.
    func send(key: Key) { self._keyPress.observer.sendNext(self.keyGenerator.create(key)); }

    @objc internal func spaceChanged(notification: NSNotification) {
        self._keyPress.observer.sendNext(self.keyGenerator.create(.Blur));
    }

    @objc internal func appDeactivated(notification: NSNotification) {
        guard let app = notification.userInfo?[NSWorkspaceApplicationKey] as? NSRunningApplication else { return; };
        if app.bundleIdentifier == "com.giantacorn.sidetalk" {
            self._keyPress.observer.sendNext(self.keyGenerator.create(.Blur));
        }
    }

    @objc internal func appActivated(notification: NSNotification) {
        guard let app = notification.userInfo?[NSWorkspaceApplicationKey] as? NSRunningApplication else { return; };
        if app.bundleIdentifier == "com.giantacorn.sidetalk" {
            self._keyPress.observer.sendNext(self.keyGenerator.create(.Focus));
        }
    }
}
