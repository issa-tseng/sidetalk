
import Foundation;
import Cocoa;
import ReactiveCocoa;
import FuzzySearch;
import enum Result.NoError;

struct LayoutState {
    let order: [ Contact : Int ];
    let state: MainState;
    let notifying: Set<Contact>;
}

// TODO: split into V/VM?
class MainView: NSView {
    internal let connection: Connection;

    private let _statusTile: StatusTile;
    private var _contactTiles = QuickCache<Contact, ContactTile>();
    private var _conversationViews = QuickCache<Contact, ConversationView>();

    private var _state: Signal<MainState, NoError>?;
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
        let latestMessage = self.connection.latestMessage;

        // draw new contacts as required.
        let tiles = self.connection.contacts.map({ (contacts) -> [ContactTile] in
            contacts.map { contact in self._contactTiles.get(contact, orElse: { self.drawContact(contact); }); };
        });

        // draw new conversations as required.
        latestMessage.observeNext { message in
            let conversation = message.conversation;
            self._conversationViews.get(conversation.with, orElse: { self.drawConversation(conversation); })
        };

        // calculate the correct sort (and implicitly visibility) of all contacts.
        let sort = self.connection.contacts
            .combineWithDefault(latestMessage.downcastToOptional(), defaultValue: nil).map({ contacts, _ in contacts })
            .combineWithDefault(self._statusTile.searchText, defaultValue: "")
            .map({ contacts, search -> [ Contact : Int ] in
                let (chattedContacts, restContacts) = contacts.part({ contact in contact.conversation.messages.count > 0 });

                let sortedChattedContacts = chattedContacts.sort({ a, b in
                    a.conversation.messages.first!.at.compare(b.conversation.messages.first!.at) == .OrderedDescending
                });

                let availableContacts = restContacts.filter { contact in contact.onlineOnce && contact.presenceOnce == nil };
                let awayContacts = restContacts.filter { contact in contact.onlineOnce && contact.presenceOnce != nil };

                var sorted: [Contact]; // HACK: mutable. gross.

                if search == "" {
                    sorted = sortedChattedContacts + availableContacts + awayContacts;
                } else {
                    let offlineContacts = restContacts.filter { contact in !contact.onlineOnce };
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

        // determine global state.
        let keyTracker = Impulse.track(Key);
        var lastState: (MainState, NSDate) = (.Normal, NSDate());
        self._state = GlobalInteraction.sharedInstance.keyPress
            .combineLatestWith(sort)
            .combineWithDefault(self._statusTile.searchText, defaultValue: "").map({ ($0.0, $0.1, $1); })
            .scan(.Inactive, { (last, args) -> MainState in
                let (wrappedKey, sort, search) = args;

                let key = keyTracker.extract(wrappedKey);
                switch (last, key) {
                case (.Normal, .Escape): return .Inactive;
                case (.Normal, .Down): return .Selecting(0);

                case (.Selecting(0), .Up): return .Normal;
                case (let .Selecting(idx), .Up): return .Selecting(idx - 1);
                case (let .Selecting(idx), .Down): return .Selecting((idx + 1 == sort.count) ? idx : idx + 1);
                case (let .Selecting(idx), .Return): return .Chatting(sort.filter({ _, sidx in idx == sidx }).first!.0);
                case (.Selecting, .Escape): return .Normal;

                case (let .Searching(text, 0), .Up): return .Searching(text, 0);
                case (let .Searching(text, idx), .Up): return .Searching(text, idx - 1);
                case (let .Searching(text, idx), .Down): return .Searching(text, (idx + 1 == sort.count) ? idx : idx + 1);
                case (let .Searching(_, idx), .Return): return .Chatting(sort.filter({ _, sidx in idx == sidx }).first!.0);
                case (.Searching, .Escape): return .Normal;

                case (.Chatting, .Escape): return .Normal;

                case (.Inactive, .GlobalToggle):
                    let (state, time) = lastState;
                    if time.dateByAddingTimeInterval(self.restoreInterval).isGreaterThan(NSDate()) { return state; }
                    else { return .Normal; }
                case (_, .GlobalToggle): return .Inactive;
                default: break;
                };

                switch (last, search) {
                case (.Normal, let text) where text != "": return .Searching(text, 0);
                case (.Selecting(_), let text) where text != "": return .Searching(text, 0);
                case (.Searching(_, _), ""): return .Normal;
                case (let .Searching(ltext, _), let ttext) where ltext != ttext: return .Searching(ttext, 0);
                default: break;
                }

                return last;
            });

        GlobalInteraction.sharedInstance.keyPress.observeNext({ next in NSLog("key: \(next)"); });
        self.state.observeNext({ next in NSLog("state: \(next)"); });

        // keep track of our last state:
        self.state.filter({ state in state != .Inactive }).observeNext({ state in lastState = (state, NSDate()); });

        // figure out which contacts currently have notification bubbles.
        let notifying = latestMessage.merge(latestMessage.delay(self.messageShown, onScheduler: scheduler)).map { _ -> Set<Contact> in
            let now = NSDate();
            var result = Set<Contact>();

            // conversation states have changed. let's look at which have recent messages.
            for conversationView in self._conversationViews.all() {
                let conversation = conversationView.conversation;
                if conversation.messages.count > 0 && conversation.messages.first!.at.dateByAddingTimeInterval(self.messageShown).isGreaterThanOrEqualTo(now) {
                    result.insert(conversation.with);
                }
            }

            return result;
        }

        // relayout as required.
        sort.combineLatestWith(tiles).map { order, _ in order } // (Order)
            .combineWithDefault(latestMessage.map({ _ in nil as AnyObject? }), defaultValue: nil).map { order, _ in order } // (Order)
            .combineWithDefault(self.state, defaultValue: .Inactive) // (Order, MainState)
            .combineWithDefault(notifying, defaultValue: Set<Contact>()) // ((Order, MainState), Set[Contact])
            .map({ orderState, notifying in LayoutState(order: orderState.0, state: orderState.1, notifying: notifying); })
            .debounce(NSTimeInterval(0.02), onScheduler: QueueScheduler.mainQueueScheduler)
            .combinePrevious(LayoutState(order: [:], state: .Inactive, notifying: Set<Contact>()))
            .observeNext { last, this in self.relayout(last, this) };

        // show or hide contact labels as appropriate.
        tiles.combineLatestWith(sort) // ([ContactTile], [Contact:Int])
            .combineWithDefault(notifying.downcastToOptional(), defaultValue: nil) // (([ContactTile], [Contact:Int]), Set<Contact>?)
            .combineWithDefault(self.state, defaultValue: .Inactive) // ((([ContactTile], [Contact:Int]), Set<Contact>?), Contact?)
            .map({ ($0.0.0, $0.0.1, $0.1, $1) }) // ([ContactTile], [Contact:Int], Set<Contact>?, Contact?)
            .observeNext { (tiles, sort, notifying, state) in
                for tile in tiles {
                    tile.showLabel = (state != .Inactive) && (state.essentially != .Chatting) && (notifying == nil || notifying!.count == 0) && (sort[tile.contact] != nil);
                }
            };

        // render only the conversation for the active contact.
        self.state
            .combineLatestWith(sort)
            .map({ (state, sort) -> Contact? in
                switch state {
                case let .Chatting(with): return with;
                default: return nil;
                }
            })
            .combinePrevious(nil)
            .observeNext { (last, this) in
                if last == this { return; }
                if let view = self._conversationViews.get(last) { view.deactivate(); }

                if let contact = this { self._conversationViews.get(contact, orElse: { self.drawConversation(contact.conversation) }).activate(); }
            };

        // upon activate/deactivate, handle window focus correctly.
        self.state.combinePrevious(.Inactive).observeNext { last, this in
            if last == .Inactive && this != .Inactive {
                NSApplication.sharedApplication().activateIgnoringOtherApps(true);
            } else if last != .Inactive && this == .Inactive {
                GlobalInteraction.sharedInstance.lastApp?.activateWithOptions(NSApplicationActivationOptions.ActivateIgnoringOtherApps);
            }
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
            if lastState.state.active != thisState.state.active {
                let tile = self._statusTile;
                let anim = CABasicAnimation.init(keyPath: "position");

                let off = NSPoint.zero;
                let on =  NSPoint(x: self.tileSize.height * -0.55, y: 0);

                if (thisState.state.active) {
                    anim.fromValue = NSValue.init(point: off);
                    anim.toValue = NSValue.init(point: on);
                } else {
                    anim.fromValue = NSValue.init(point: on);
                    anim.toValue = NSValue.init(point: off);
                }

                anim.duration = thisState.state.active ? 0.03 : 0.15;
                anim.fillMode = kCAFillModeForwards; // HACK: i don't like this or the next line.
                anim.removedOnCompletion = false;
                tile.layer!.removeAnimationForKey("contacttile-layout");
                tile.layer!.addAnimation(anim, forKey: "contacttile-layout");
                tile.layer!.position = thisState.state.active ? on : off;
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

                // TODO: repetitive.
                switch (last, lastState.notifying.contains(tile.contact), lastState.state) {
                case (nil, _, _):                                               from = NSPoint(x: xOff, y: yThis);
                case (let lidx, _, let .Selecting(idx)) where lidx == idx:      from = NSPoint(x: xOn, y: yLast);
                case (let lidx, _, let .Searching(_, idx)) where lidx == idx:   from = NSPoint(x: xOn, y: yLast);
                case (_, _, let .Chatting(with)) where with == tile.contact:    from = NSPoint(x: xOn, y: yLast);
                case (_, _, .Normal), (_, true, _):                             from = NSPoint(x: xOn, y: yLast);
                default:                                                        from = NSPoint(x: xHalf, y: yLast);
                }

                switch (this, thisState.notifying.contains(tile.contact), thisState.state) {
                case (nil, _, _):                                               to = NSPoint(x: xOff, y: yLast);
                case (let tidx, _, let .Selecting(idx)) where tidx == idx:      to = NSPoint(x: xOn, y: yThis);
                case (let tidx, _, let .Searching(_, idx)) where tidx == idx:   to = NSPoint(x: xOn, y: yThis);
                case (_, _, let .Chatting(with)) where with == tile.contact:    to = NSPoint(x: xOn, y: yThis);
                case (_, _, .Normal), (_, true, _):                             to = NSPoint(x: xOn, y: yThis);
                default:                                                        to = NSPoint(x: xHalf, y: yThis);
                }

                if tile.layer!.position != to {
                    anim.fromValue = NSValue.init(point: from);
                    anim.toValue = NSValue.init(point: to);
                    anim.duration = NSTimeInterval((!lastState.state.active && thisState.state.active ? 0.05 : 0.2) + (0.02 * Double(this ?? 0)));
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
