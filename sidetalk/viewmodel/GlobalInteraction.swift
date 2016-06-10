
import Foundation
import MASShortcut
import ReactiveCocoa
import enum Result.NoError

class GlobalInteraction {
    static let sharedInstance = GlobalInteraction();

    var lastApp: NSRunningApplication?;

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
