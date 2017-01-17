
import Foundation

class ContactMenu {
    private let menu: NSMenu;
    private let mainView: MainView;
    private let jid: String;

    internal init(contact: Contact, mainView: MainView) {
        self.jid = contact.inner.jid().full();
        self.mainView = mainView;
        self.menu = NSMenu(title: contact.displayName);

        self.menu.addItem(NSMenuItem(title: self.jid, action: #selector(noop), keyEquivalent: ""));
        self.menu.addItem(NSMenuItem.separatorItem());

        let starItem = NSMenuItem(title: "Star", action: #selector(star), keyEquivalent: "");
        starItem.state = mainView.starredJids.contains(self.jid) ? NSOnState : NSOffState;
        starItem.target = self;
        starItem.enabled = true;
        self.menu.addItem(starItem);

        let hideItem = NSMenuItem(title: "Hide", action: #selector(hide), keyEquivalent: "");
        hideItem.state = mainView.hiddenJids.contains(self.jid) ? NSOnState : NSOffState;
        hideItem.target = self;
        hideItem.enabled = true;
        self.menu.addItem(hideItem);
    }

    @objc func star() {
        self.mainView.starredJids.toggle(self.jid);
    }

    @objc func hide() {
        self.mainView.hiddenJids.toggle(self.jid);
    }

    @objc func noop() {}

    func show(event: NSEvent) {
        NSMenu.popUpContextMenu(self.menu, withEvent: event, forView: self.mainView);
    }

    static func show(contact: Contact, event: NSEvent, view: MainView) {
        let instance = ContactMenu(contact: contact, mainView: view);
        instance.show(event);
    }
}
