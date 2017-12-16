
import Foundation;
import MASShortcut;
import ReactiveSwift;
import enum Result.NoError;

enum Key: Impulsable {
    case Up, Down, Return, LineBreak, Escape, GlobalToggle, Focus, Blur, Click, None;

    static func noopValue() -> Key { return .None; }
}

class GlobalInteraction {
    static let sharedInstance = GlobalInteraction();

    private let keyGenerator = Impulse.generate(Key.self);
    private let _keyPress = ManagedSignal<Impulse<Key>>();
    var keyPress: Signal<Impulse<Key>, NoError> { get { return self._keyPress.signal; } };

    private let anyModifierMask = NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.control.rawValue;

    init() {
        // we'll want to blur when the space changes, or we lose focus. and activate if the app is activated from the dock.
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil);
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(appDeactivated), name: NSWorkspace.didDeactivateApplicationNotification, object: nil);
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil);

        // listen to all key events. vend keystroke.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            if event.keyCode == 126 { // up
                self._keyPress.observer.send(value: self.keyGenerator.create(.Up));
            } else if event.keyCode == 125 { // down
                self._keyPress.observer.send(value: self.keyGenerator.create(.Down));
            } else if event.keyCode == 36 { // enter
                if (event.modifierFlags.rawValue & self.anyModifierMask) > 0 {
                    self._keyPress.observer.send(value: self.keyGenerator.create(.LineBreak));
                } else {
                    self._keyPress.observer.send(value: self.keyGenerator.create(.Return));
                }
            } else if event.keyCode == 53 { // esc
                self._keyPress.observer.send(value: self.keyGenerator.create(.Escape));
            }
            return event;
        });

        // global shortcut.
        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: "globalActivation", toAction: {
            self._keyPress.observer.send(value: self.keyGenerator.create(.GlobalToggle));
        });
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self);
    }

    // this is nasty. we can track the most-recently-focused app before sidetalk, but that's ignorant
    // of which space that was on. so we grab the entire window stack and try to activate whatever is just
    // below us. if we can't find that, just give up.
    func relinquish() {
        // get our own application. if there isn't one, don't do anything.
        guard let ownApp = NSWorkspace.shared.frontmostApplication else { return; }

        // nothing to be done if we're already blurred.
        if ownApp.bundleIdentifier != "com.giantacorn.sidetalk" { return; }

        // get the entire stack of currently-visible real windows.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], CGWindowID(0)) else { return; }

        // iterate til we find ourself. then find the next window down and activate that.
        var foundSelf = false;
        for x in windows {
            let window = x as! [CFString: Any];
            if !foundSelf && window[kCGWindowOwnerName] as? String == ownApp.localizedName {
                foundSelf = true;
                continue;
            }

            // window layer of 0 is normalspace.
            if foundSelf && (window[kCGWindowLayer] as? Int) == 0 {
                let pid = window[kCGWindowOwnerPID] as! CFNumber;
                if let application = NSWorkspace.shared.runningApplications.find({ app in Int(app.processIdentifier) == Int(truncating: pid) }) {
                    application.activate(options: NSApplication.ActivationOptions.activateIgnoringOtherApps);
                    return;
                }
            }
        }
    }

    // HACK: i don't like that this is just sort of sitting around.
    func send(_ key: Key) { self._keyPress.observer.send(value: self.keyGenerator.create(key)); }

    @objc internal func spaceChanged(notification: NSNotification) {
        self._keyPress.observer.send(value: self.keyGenerator.create(.Blur));
    }

    @objc internal func appDeactivated(notification: NSNotification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return; };
        if app.bundleIdentifier == "com.giantacorn.sidetalk" {
            self._keyPress.observer.send(value: self.keyGenerator.create(.Blur));
        }
    }

    @objc internal func appActivated(notification: NSNotification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return; };
        if app.bundleIdentifier == "com.giantacorn.sidetalk" {
            self._keyPress.observer.send(value: self.keyGenerator.create(.Focus));
        }
    }
}
