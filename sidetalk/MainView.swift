
import Foundation
import Cocoa
import ReactiveCocoa
import FuzzySearch

struct LayoutState {
    let order: [ Contact : Int ];
    let activated: Bool;
    let notifying: Set<Contact>;
    let selected: Int?;
}

enum Key {
    case Up, Down, Return, Escape, None;
}

// TODO: split into V/VM?
class MainView: NSView {
    internal let connection: Connection;

    private let _statusTile: StatusTile;
    private var _contactTiles = QuickCache<Contact, ContactTile>();
    private var _conversationViews = QuickCache<Contact, ConversationView>();

    // drawing ks. should these go elsewhere?
    let allPadding = CGFloat(150);
    let listPadding = CGFloat(35);
    let tileSize = NSSize(width: 300, height: 50);
    let tilePadding = CGFloat(4);
    let conversationPadding = CGFloat(14);
    let conversationWidth = CGFloat(300);
    let conversationVOffset = CGFloat(12.0);

    let messageShown = NSTimeInterval(3.0);

    private let _pressedKey = ManagedSignal<Key>();

    // fuck you mutable state!
    private var _activeContact: Contact?;

    init(frame: CGRect, connection: Connection) {
        self.connection = connection;
        self._statusTile = StatusTile(connection: connection, frame: NSRect(origin: NSPoint.zero, size: frame.size));

        super.init(frame: frame);

        self.addSubview(self._statusTile);
        self._statusTile.frame.origin = NSPoint(
            x: frame.width - self.tileSize.width - self.tilePadding + (self.tileSize.height * 0.55),
            y: frame.height - self.allPadding
        );

        self.prepare();
    }

    private func prepare() {
        let conversations = self.connection.conversations;

        // listen to all key events. vend keystroke.
        NSEvent.addLocalMonitorForEventsMatchingMask(.KeyDownMask, handler: { event in
            if event.keyCode == 126 {
                // up
                self._pressedKey.observer.sendNext(.Up);
                self._pressedKey.observer.sendNext(.None);
                return nil;
            } else if event.keyCode == 125 {
                // down
                self._pressedKey.observer.sendNext(.Down);
                self._pressedKey.observer.sendNext(.None);
                return nil;
            } else if event.keyCode == 36 {
                // enter
                self._pressedKey.observer.sendNext(.Return);
                self._pressedKey.observer.sendNext(.None);
                return event;
            } else if event.keyCode == 53 {
                // enter
                self._pressedKey.observer.sendNext(.Escape);
                self._pressedKey.observer.sendNext(.None);
                return event;
            } else {
                return event;
            }
        });

        // draw new contacts as required.
        let tiles = self.connection.contacts.map({ (contacts) -> [ContactTile] in
            contacts.map { contact in self._contactTiles.get(contact, orElse: { self.drawContact(contact); }); };
        });

        // draw new conversations as required.
        let conversationViews = conversations.map { conversations in
            conversations.map { conversation in self._conversationViews.get(conversation.with, orElse: { self.drawConversation(conversation); }) };
        }

        // figure out which contacts currently have notification bubbles.
        let scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "delayed-messages-mainview");
        let notifying = conversations.merge(conversations.delay(self.messageShown, onScheduler: scheduler)).map { _ -> Set<Contact> in
            let now = NSDate();
            var result = Set<Contact>();

            // conversation states have changed. let's look at which have recent messages.
            for conversationView in self._conversationViews.all() {
                let conversation = conversationView.conversation;
                if conversation.messages.count > 0 && conversation.messages.last!.at.dateByAddingTimeInterval(self.messageShown).isGreaterThanOrEqualTo(now) {
                    result.insert(conversation.with);
                }
            }

            return result;
        }

        // calculate the correct sort (and implicitly visibility) of all contacts.
        let sort = self.connection.contacts
            .combineWithDefault(self._statusTile.searchText, defaultValue: "")
            .map({ contacts, search -> [ Contact : Int ] in
                let availableContacts = contacts.filter({ contact in contact.onlineOnce && contact.presenceOnce == nil });
                let awayContacts = contacts.filter { contact in contact.onlineOnce && contact.presenceOnce != nil };

                var sorted: [Contact]; // HACK: mutable. gross.

                if search == "" {
                    sorted = availableContacts + awayContacts;
                } else {
                    let offlineContacts = contacts.filter { contact in !contact.onlineOnce };
                    let scores = (availableContacts + awayContacts + offlineContacts).map { contact in
                        (contact, FuzzySearch.score(originalString: contact.displayName, stringToMatch: search, fuzziness: 0.75));
                    };

                    let maxScore = scores.map({ (_, score) in score }).maxElement();
                    sorted = scores.filter({ (_, score) in score > maxScore! - 0.2 && score > 0.1 }).map({ (contact, _) in contact });
                }

                var result = Dictionary<Contact, Int>();
                for (idx, contact) in sorted.enumerate() {
                    result[contact] = idx;
                }
                return result;
            });

        // determine currently-selected index.
        let selectedIdx = GlobalInteraction.sharedInstance.activated // (Bool)
            .combineWithDefault(self._statusTile.searchText, defaultValue: "") // (Bool, String)
            .combineWithDefault(sort, defaultValue: [Contact:Int]()).map({ ($0.0, $0.1, $1) }) // (Bool, String, [Contact:Int])
            .combineWithDefault(self._pressedKey.signal, defaultValue: .None).map({ ($0.0, $0.1, $0.2, $1) }) // (Bool, String, [Contact:Int], Key)
            .combinePrevious((false, "", [:], .None))
            .scan(nil, { (lastIdx, states) -> Int? in
                let (_, lastSearch, _, _) = states.0;
                let (activated, thisSearch, contacts, direction) = states.1;

                if !activated {
                    return nil;
                } else if self._activeContact != nil {
                    return lastIdx;
                } else if direction == .Up {
                    if lastIdx == nil { return nil; }
                    else if lastIdx == 0 { return nil; }
                    else if lastIdx > 0 { return lastIdx! - 1; }
                } else if direction == .Down {
                    if lastIdx == nil { return 0; }
                    else if lastIdx == (contacts.count - 1) { return lastIdx; }
                    else { return lastIdx! + 1; }
                } else if lastSearch != thisSearch {
                    if thisSearch == "" { return nil; }
                    else { return 0; }
                }

                return lastIdx;
            });

        // relayout as required.
        sort.combineLatestWith(tiles).map { order, _ in order } // (Order)
            .combineWithDefault(conversationViews.map({ _ in nil as AnyObject? }), defaultValue: nil).map { order, _ in order } // (Order)
            .combineWithDefault(GlobalInteraction.sharedInstance.activated, defaultValue: false) // (Order, Bool)
            .combineWithDefault(notifying, defaultValue: Set<Contact>()).map({ ($0.0, $0.1, $1) }) // ((Order, Bool, Set[Contact])
            .combineWithDefault(selectedIdx, defaultValue: nil) // ((Order, Bool, Set[Contact]), selectedIdx)
            .map({ bigTuple, selected in LayoutState(order: bigTuple.0, activated: bigTuple.1, notifying: bigTuple.2, selected: selected); })
            .debounce(NSTimeInterval(0.02), onScheduler: QueueScheduler.mainQueueScheduler)
            .combinePrevious(LayoutState(order: [:], activated: false, notifying: Set<Contact>(), selected: nil))
            .observeNext { last, this in self.relayout(last, this) };

        // if someone presses return while something is selected, activate that conversation (only).
        let activeContact = self._pressedKey.signal // (Key)
            .combineWithDefault(selectedIdx, defaultValue: nil) // (Key, Int?)
            .combineLatestWith(sort).map({ ($0.0, $0.1, $1) }) // (Key, Int?, [Contact:Int])
            .scan(nil, { (last, state) -> Contact? in
                let (key, idx, sort) = state;
                if key == .Return && idx != nil {
                    return sort.filter({ _, sortIdx in idx == sortIdx }).first!.0;
                } else if key == .Escape {
                    return nil;
                } else {
                    return last;
                }
            });

        activeContact
            .combinePrevious(nil)
            .observeNext { last, this in
                if last == this { return; }
                if let view = self._conversationViews.get(last) { view.deactivate(); }
                if let view = self._conversationViews.get(this) { view.activate(); }
                self._activeContact = this;
        };

        // if we are active and no notifications are present, show all contact labels.
        tiles.combineLatestWith(GlobalInteraction.sharedInstance.activated)
            .combineLatestWith(sort) // (([ContactTile], Bool), [Contact:Int])
            .combineWithDefault(notifying.map({ $0 as Set<Contact>? }), defaultValue: nil) // ((([ContactTile], Bool), [Contact:Int]), Set<Contact>?)
            .combineWithDefault(activeContact, defaultValue: nil) // (((([ContactTile], Bool), [Contact:Int]), Set<Contact>?), Contact?)
            .map({ ($0.0.0.0, $0.0.0.1, $0.0.1, $0.1, $1) }) // ([ContactTile], Bool, [Contact:Int], Set<Contact>?, Contact?)
            .observeNext { (tiles, activated, sort, notifying, activeContact) in
                for tile in tiles {
                    tile.showLabel = activated && (notifying == nil || notifying!.count == 0) && (sort[tile.contact] != nil) && (activeContact == nil);
                }
            };

        // if we are active, claim window focus. vice versa.
        GlobalInteraction.sharedInstance.activated.observeNext { activated in
            if activated { NSApplication.sharedApplication().activateIgnoringOtherApps(true); }
            else         { GlobalInteraction.sharedInstance.lastApp?.activateWithOptions(NSApplicationActivationOptions.ActivateIgnoringOtherApps); }
        }
    }

    private func drawContact(contact: Contact) -> ContactTile {
        let newTile = ContactTile(
            frame: self.frame,
            size: tileSize,
            contact: contact
        );
        dispatch_async(dispatch_get_main_queue(), { self.addSubview(newTile); });
        return newTile;
    }

    private func drawConversation(conversation: Conversation) -> ConversationView {
        let newView = ConversationView(
            frame: self.frame,
            width: self.conversationWidth,
            conversation: conversation
        );
        self._contactTiles.get(conversation.with)!.attachConversation(newView);
        dispatch_async(dispatch_get_main_queue(), { self.addSubview(newView); });
        return newView;
    }

    private func relayout(lastState: LayoutState, _ thisState: LayoutState) {
        // TODO: figure out the two hacks below ( http://stackoverflow.com/questions/37780431/cocoa-core-animation-everything-jumps-around-upon-becomefirstresponder )
        dispatch_async(dispatch_get_main_queue(), {
            // deal with self
            if lastState.activated != thisState.activated {
                let tile = self._statusTile;
                let anim = CABasicAnimation.init(keyPath: "position");

                let off = NSPoint.zero;
                let on =  NSPoint(x: self.tileSize.height * -0.55, y: 0);

                if (thisState.activated) {
                    anim.fromValue = NSValue.init(point: off);
                    anim.toValue = NSValue.init(point: on);
                } else {
                    anim.fromValue = NSValue.init(point: on);
                    anim.toValue = NSValue.init(point: off);
                }

                anim.duration = thisState.activated ? 0.03 : 0.15;
                anim.fillMode = kCAFillModeForwards; // HACK: i don't like this or the next line.
                anim.removedOnCompletion = false;
                tile.layer!.removeAnimationForKey("contacttile-layout");
                tile.layer!.addAnimation(anim, forKey: "contacttile-layout");
                tile.layer!.position = thisState.activated ? on : off;
            }

            // deal with actual contacts
            for tile in self._contactTiles.all() {
                let anim = CABasicAnimation.init(keyPath: "position");

                let last = lastState.order[tile.contact];
                let this = thisState.order[tile.contact];

                // make sure we're offscreen if we're not to be shown
                if last == nil && this == nil {
                    tile.hidden = true;
                    continue;
                } else {
                    tile.hidden = false;
                }

                // calculate positions. TODO: mutable. gross.
                var from: NSPoint;
                var to: NSPoint;

                let xOn = self.frame.width - self.tileSize.width - self.tilePadding;
                let xHalf = self.frame.width - self.tileSize.width + (self.tileSize.height * 0.55);
                let xOff = self.frame.width - self.tileSize.width + self.tileSize.height;

                let yLast = self.frame.height - self.allPadding - self.listPadding - ((self.tileSize.height + self.tilePadding) * CGFloat((last ?? 0) + 1));
                let yThis = self.frame.height - self.allPadding - self.listPadding - ((self.tileSize.height + self.tilePadding) * CGFloat((this ?? 0) + 1));

                if last == nil { from = NSPoint(x: xOff, y: yThis); }
                else if (lastState.activated || lastState.notifying.contains(tile.contact)) &&
                        (lastState.selected == nil || lastState.selected == last) { from = NSPoint(x: xOn, y: yLast); }
                else { from = NSPoint(x: xHalf, y: yLast); }

                if this == nil { to = NSPoint(x: xOff, y: yLast); }
                else if (thisState.activated || thisState.notifying.contains(tile.contact)) &&
                        (thisState.selected == nil || thisState.selected == this) { to = NSPoint(x: xOn, y: yThis); }
                else { to = NSPoint(x: xHalf, y: yThis); }

                if tile.layer!.position != to {
                    anim.fromValue = NSValue.init(point: from);
                    anim.toValue = NSValue.init(point: to);
                    anim.duration = NSTimeInterval((!lastState.activated && thisState.activated ? 0.05 : 0.2) + (0.02 * Double(this ?? 0)));
                    anim.fillMode = kCAFillModeForwards; // HACK: i don't like this or the next line.
                    anim.removedOnCompletion = false;
                    tile.layer!.removeAnimationForKey("contacttile-layout");
                    tile.layer!.addAnimation(anim, forKey: "contacttile-layout");
                    tile.layer!.position = to;
                }

                // if we have a conversation as well, position that appropriately.
                if let conversationView = self._conversationViews.get(tile.contact) {
                    let convAnim = CABasicAnimation.init(keyPath: "position");
                    let convX = self.frame.width - self.tileSize.height - self.tilePadding - self.conversationPadding - self.conversationWidth;
                    let from = NSPoint(x: convX, y: yLast + self.conversationVOffset);
                    let to = NSPoint(x: convX, y: yThis + self.conversationVOffset);

                    if conversationView.layer!.position != to {
                        convAnim.fromValue = NSValue.init(point: from);
                        convAnim.toValue = NSValue.init(point: to);
                        convAnim.duration = anim.duration;
                        convAnim.fillMode = kCAFillModeForwards; // HACK: i don't like this or the next line.
                        convAnim.removedOnCompletion = false;
                        conversationView.layer!.removeAnimationForKey("conversation-layout");
                        conversationView.layer!.addAnimation(convAnim, forKey: "conversation-layout");
                        conversationView.layer!.position = to;
                    }
                }
            }
        });
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
