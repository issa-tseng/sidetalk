
import Foundation;
import Cocoa;
import ReactiveCocoa;
import FuzzySearch;
import enum Result.NoError;

struct LayoutState {
    let order: [ Contact : Int ];
    let state: MainState;
    let notifying: Set<Contact>;
    let selected: Int?;
}

enum MainState: Impulsable {
    case Inactive, Normal, Searching, Selecting, Chatting, None;
    static func noopValue() -> MainState { return .None; }

    func isActive() -> Bool { return !(self == .Inactive || self == .None); }
}

// TODO: split into V/VM?
class MainView: NSView {
    internal let connection: Connection;

    private let _statusTile: StatusTile;
    private var _contactTiles = QuickCache<Contact, ContactTile>();
    private var _conversationViews = QuickCache<Contact, ConversationView>();

    private var _state: Signal<MainState, NoError>?;
    private let _stateOverride = ManagedSignal<Impulse<MainState>>();
    var state: Signal<MainState, NoError> { get { return self._state!; } };

    // drawing ks. should these go elsewhere?
    let allPadding = CGFloat(150);
    let listPadding = CGFloat(35);
    let tileSize = NSSize(width: 300, height: 50);
    let tilePadding = CGFloat(4);
    let conversationPadding = CGFloat(14);
    let conversationWidth = CGFloat(300);
    let conversationVOffset = CGFloat(-17);

    let messageShown = NSTimeInterval(3.0);
    let restoreInterval = NSTimeInterval(30.0);

    private let _pressedKey = ManagedSignal<Key>();

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
        self._statusTile.prepare(self.state);
    }

    private func prepare() {
        let scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "mainview-scheduler");
        let conversations = self.connection.conversations;

        // determine global state.
        let globalStateKeyTracker = Impulse.track(Key);
        let globalStateOverrideTracker = Impulse.track(MainState);
        self._state = self._stateOverride.signal
            .combineWithDefault(self._statusTile.searchText, defaultValue: "")
            .combineWithDefault(GlobalInteraction.sharedInstance.keyPress.map({ $0 as Impulse<Key>? }), defaultValue: nil).map({ ($0.0, $0.1, $1); })
            .scan(.Inactive, { (last, args) -> MainState in
                let (wrappedOverride, search, wrappedKey) = args;

                let override = globalStateOverrideTracker.extract(wrappedOverride);
                if override != .None { return override; }

                if (last == .Searching) && (search == "") { return .Normal; }

                let key = globalStateKeyTracker.extract(wrappedKey);
                switch (last, key) {
                //case (.Normal, .Escape): return .Inactive;
                case (.Normal, .Down): return .Selecting;
                case (.Selecting, .Return): return .Chatting;
                case (.Selecting, .Escape): return .Normal;
                case (.Searching, .Return): return .Chatting;
                case (.Searching, .Escape): return .Normal;
                case (.Chatting, .Escape): return .Normal;
                default: break;
                };

                if (last == .Normal || last == .Selecting) && (search != "") { return .Searching; }

                return last;
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

        // determine the current index.
        let selectedIdxKeyTracker = Impulse.track(Key);
        let selectedIdx = sort
            .combineLatestWith(self.state)
            .combineLatestWith(GlobalInteraction.sharedInstance.keyPress).map({ ($0.0, $0.1, $1) })
            .debounce(NSTimeInterval(0.1), onScheduler: scheduler) // HACK: this is a band-aid at best.
            .scan(nil, { (last, args) -> Int? in
                let (sort, state, wrappedKey) = args;

                if state == .Chatting { return last; }
                if state != .Searching && state != .Selecting { return nil; }
                if last == nil { return 0; }

                let key = selectedIdxKeyTracker.extract(wrappedKey);
                if state == .Searching && key == .None {
                    return 0;
                } else if key == .Up {
                    if last > 0 {
                        return last! - 1;
                    } else if state == .Selecting {
                        //self.pushState(.Normal); // HACK: side effects
                        return nil;
                    } else {
                        return 0;
                    }
                } else if key == .Down {
                    if last == (sort.count - 1) {
                        return last;
                    } else {
                        return last! + 1;
                    }
                }
                return last; // should never be called.
            });

        // relayout as required.
        sort.combineLatestWith(tiles).map { order, _ in order } // (Order)
            .combineWithDefault(conversationViews.map({ _ in nil as AnyObject? }), defaultValue: nil).map { order, _ in order } // (Order)
            .combineWithDefault(self.state, defaultValue: .Inactive) // (Order, MainState)
            .combineWithDefault(notifying, defaultValue: Set<Contact>()).map({ ($0.0, $0.1, $1) }) // ((Order, MainState, Set[Contact])
            .combineWithDefault(selectedIdx, defaultValue: nil) // ((Order, MainState, Set[Contact]), selectedIdx)
            .map({ bigTuple, selected in LayoutState(order: bigTuple.0, state: bigTuple.1, notifying: bigTuple.2, selected: selected); })
            .debounce(NSTimeInterval(0.02), onScheduler: QueueScheduler.mainQueueScheduler)
            .combinePrevious(LayoutState(order: [:], state: .Inactive, notifying: Set<Contact>(), selected: nil))
            .observeNext { last, this in self.relayout(last, this) };

        // show or hide contact labels as appropriate.
        tiles.combineLatestWith(GlobalInteraction.sharedInstance.activated)
            .combineLatestWith(sort) // (([ContactTile], Bool), [Contact:Int])
            .combineWithDefault(notifying.map({ $0 as Set<Contact>? }), defaultValue: nil) // ((([ContactTile], Bool), [Contact:Int]), Set<Contact>?)
            .combineWithDefault(self.state, defaultValue: .Inactive) // (((([ContactTile], Bool), [Contact:Int]), Set<Contact>?), Contact?)
            .map({ ($0.0.0.0, $0.0.0.1, $0.0.1, $0.1, $1) }) // ([ContactTile], Bool, [Contact:Int], Set<Contact>?, Contact?)
            .observeNext { (tiles, activated, sort, notifying, state) in
                for tile in tiles {
                    tile.showLabel = activated && (notifying == nil || notifying!.count == 0) && (sort[tile.contact] != nil) && (state != .Chatting);
                }
            };

        // render only the conversation for the active contact.
        selectedIdx
            .combineLatestWith(self.state)
            .combineLatestWith(sort).map({ ($0.0, $0.1, $1); })
            .map({ (idx, state, sort) -> Contact? in
                if state == .Chatting && idx != nil { return sort.filter({ _, cidx in idx == cidx }).first!.0; }
                else { return nil; }
            })
            .combinePrevious(nil)
            .observeNext { (last, this) in
                if last == this { return; }
                if let view = self._conversationViews.get(last) { view.deactivate(); }
                if let view = self._conversationViews.get(this) { view.activate(); }
            };

        // keep track of our last state:
        var lastState: (MainState, NSDate) = (.Normal, NSDate());

        // upon activate/deactivate, push the relevant state.
        GlobalInteraction.sharedInstance.activated.observeNext { activated in
            if activated {
                NSApplication.sharedApplication().activateIgnoringOtherApps(true);

                let (state, time) = lastState;
                if time.dateByAddingTimeInterval(self.restoreInterval).isGreaterThan(NSDate()) {
                    self.pushState(state);
                } else {
                    self.pushState(.Normal);
                }
            } else {
                GlobalInteraction.sharedInstance.lastApp?.activateWithOptions(NSApplicationActivationOptions.ActivateIgnoringOtherApps);
                self.pushState(.Inactive);
            }
        }

        // remember the last non-inactive state.
        self.state.filter({ state in state != .Inactive }).observeNext({ state in lastState = (state, NSDate()); });
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

    private let overrideGenerator = Impulse.generate(MainState);
    private func pushState(state: MainState) {
        self._stateOverride.observer.sendNext(overrideGenerator.create(state));
    }

    private func relayout(lastState: LayoutState, _ thisState: LayoutState) {
        // TODO: figure out the two hacks below ( http://stackoverflow.com/questions/37780431/cocoa-core-animation-everything-jumps-around-upon-becomefirstresponder )
        dispatch_async(dispatch_get_main_queue(), {
            // deal with self
            if lastState.state.isActive() != thisState.state.isActive() {
                let tile = self._statusTile;
                let anim = CABasicAnimation.init(keyPath: "position");

                let off = NSPoint.zero;
                let on =  NSPoint(x: self.tileSize.height * -0.55, y: 0);

                if (thisState.state.isActive()) {
                    anim.fromValue = NSValue.init(point: off);
                    anim.toValue = NSValue.init(point: on);
                } else {
                    anim.fromValue = NSValue.init(point: on);
                    anim.toValue = NSValue.init(point: off);
                }

                anim.duration = thisState.state.isActive() ? 0.03 : 0.15;
                anim.fillMode = kCAFillModeForwards; // HACK: i don't like this or the next line.
                anim.removedOnCompletion = false;
                tile.layer!.removeAnimationForKey("contacttile-layout");
                tile.layer!.addAnimation(anim, forKey: "contacttile-layout");
                tile.layer!.position = thisState.state.isActive() ? on : off;
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
                else if (lastState.state.isActive() || lastState.notifying.contains(tile.contact)) &&
                        (lastState.selected == nil || lastState.selected == last) { from = NSPoint(x: xOn, y: yLast); }
                else { from = NSPoint(x: xHalf, y: yLast); }

                if this == nil { to = NSPoint(x: xOff, y: yLast); }
                else if (thisState.state.isActive() || thisState.notifying.contains(tile.contact)) &&
                        (thisState.selected == nil || thisState.selected == this) { to = NSPoint(x: xOn, y: yThis); }
                else { to = NSPoint(x: xHalf, y: yThis); }

                if tile.layer!.position != to {
                    anim.fromValue = NSValue.init(point: from);
                    anim.toValue = NSValue.init(point: to);
                    anim.duration = NSTimeInterval((!lastState.state.isActive() && thisState.state.isActive() ? 0.05 : 0.2) + (0.02 * Double(this ?? 0)));
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
