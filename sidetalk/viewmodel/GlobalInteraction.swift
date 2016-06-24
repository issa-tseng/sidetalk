
import Foundation
import MASShortcut
import ReactiveCocoa
import enum Result.NoError

enum Key : Impulsable {
    case Up, Down, Return, Escape, None;

    static func noopValue() -> Key { return .None; }
}

class GlobalInteraction {
    static let sharedInstance = GlobalInteraction();

    var lastApp: NSRunningApplication?;

    private let _keyPress = ManagedSignal<Impulse<Key>>();
    var keyPress: Signal<Impulse<Key>, NoError> { get { return self._keyPress.signal; } };

    private let activateShortcut = MASShortcut.init(keyCode: 0x31, modifierFlags: NSEventModifierFlags.ControlKeyMask.rawValue);
    private var _activated = false;
    private let _activatedSignal = ManagedSignal<Bool>();
    var activated: Signal<Bool, NoError> { get { return self._activatedSignal.signal; } };

    init() {
        // global shortcut.
        MASShortcutMonitor.sharedMonitor().registerShortcut(activateShortcut, withAction: {
            self._activated = !self._activated;
            self._activatedSignal.observer.sendNext(self._activated);
        });

        // previously focused application handling.
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(self,
            selector: #selector(appDeactivated), name: NSWorkspaceDidDeactivateApplicationNotification, object: nil);

        // listen to all key events. vend keystroke.
        let keyGenerator = Impulse.generate(Key);
        NSEvent.addLocalMonitorForEventsMatchingMask(.KeyDownMask, handler: { event in
            if event.keyCode == 126 { // up
                self._keyPress.observer.sendNext(keyGenerator.create(.Up));
            } else if event.keyCode == 125 { // down
                self._keyPress.observer.sendNext(keyGenerator.create(.Down));
            } else if event.keyCode == 36 { // enter
                self._keyPress.observer.sendNext(keyGenerator.create(.Return));
            } else if event.keyCode == 53 { // esc
                self._keyPress.observer.sendNext(keyGenerator.create(.Escape));
            }
            return event;
        });
    }

    deinit {
        NSWorkspace.sharedWorkspace().notificationCenter.removeObserver(self);
    }

    @objc internal func appDeactivated(notification: NSNotification) {
        let lastApp = notification.userInfo?[NSWorkspaceApplicationKey] as? NSRunningApplication;
        if lastApp != nil && lastApp!.bundleIdentifier != "com.giantacorn.sidetalk" {
            self.lastApp = lastApp;
        }
    }
}
