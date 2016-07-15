
import Foundation;
import Cocoa;
import ReactiveCocoa;
import FuzzySearch;
import enum Result.NoError;

struct LayoutState {
    let order: [ Contact : Int ];
    let state: MainState;
    let notifying: Set<Contact>;
    let hidden: Bool;
    let mouseIdx: Int?;
}

// TODO: split into V/VM?
class MainView: NSView {
    internal let connection: Connection;

    private let _statusTile: StatusTile;
    private var _contactTiles = QuickCache<Contact, ContactTile>();
    private var _conversationViews = QuickCache<Contact, ConversationView>();

    private var marginTracker: NSTrackingArea?;
    private var contactTracker: NSTrackingArea?;

    private var _state: Signal<MainState, NoError>?;
    private var state_: MainState = .Inactive;
    var state: Signal<MainState, NoError> { get { return self._state!; } };

    private let _mouseIdx = MutableProperty<Int?>(nil);
    var mouseIdx: Signal<Int?, NoError> { get { return self._mouseIdx.signal.skipRepeats({ a, b in a == b }); } };

    private let _hiddenMode = MutableProperty<Bool>(false);
    var hiddenMode: Signal<Bool, NoError> { get { return self._hiddenMode.signal; } };

    private let _mutedMode = MutableProperty<Bool>(false);
    var mutedMode: Signal<Bool, NoError> { get { return self._mutedMode.signal; } };
    var mutedMode_: Bool { get { return self._mutedMode.value; } };

    // drawing ks. should these go elsewhere?
    let allPadding = CGFloat(12);
    let listPadding = CGFloat(73);
    let tileSize = NSSize(width: 300, height: 50);
    let tilePadding = CGFloat(4);
    let conversationPadding = CGFloat(14);
    let conversationWidth = CGFloat(300);
    let conversationVOffset = CGFloat(-72);

    let messageShown = NSTimeInterval(5.0);
    let restoreInterval = NSTimeInterval(10.0 * 60.0);

    private let _pressedKey = ManagedSignal<Key>();

    init(frame: CGRect, connection: Connection) {
        self.connection = connection;
        self._statusTile = StatusTile(connection: connection, frame: NSRect(origin: NSPoint.zero, size: frame.size));

        super.init(frame: frame);

        self.addSubview(self._statusTile);
        self._statusTile.frame.origin = NSPoint(
            x: frame.width - self.tileSize.width - self.tilePadding + (self.tileSize.height * 0.55),
            y: self.allPadding
        );

        self.prepare();
        self._statusTile.prepare(self);

        self.marginTracker = NSTrackingArea(rect: NSRect(origin: NSPoint(x: frame.width - 2, y: 0), size: frame.size),
                                            options: [.MouseEnteredAndExited, .ActiveAlways], owner: self, userInfo: nil);
        self.addTrackingArea(self.marginTracker!);
    }

    func setHide(hidden: Bool) { self._hiddenMode.modify({ _ in hidden }); }
    func setMute(muted: Bool) { self._mutedMode.modify({ _ in muted }); }

    override func mouseEntered(theEvent: NSEvent) {
        if (theEvent.trackingArea == self.marginTracker) {
            self.liveMouse();
            self.processMouse(theEvent.locationInWindow.y);
        }
    }
    override func mouseMoved(theEvent: NSEvent) {
        self.processMouse(theEvent.locationInWindow.y);
    }
    override func mouseExited(theEvent: NSEvent) {
        if (theEvent.trackingArea == self.contactTracker) {
            if self.state_ == .Inactive { self.killMouse(); }
            self._mouseIdx.modify { _ in nil };
        }
    }

    private func liveMouse() {
        if self.contactTracker == nil {
            self.contactTracker = NSTrackingArea(rect: NSRect(origin: NSPoint(x: frame.width - self.tileSize.height - self.tilePadding, y: 0), size: frame.size),
                                                 options: [.MouseEnteredAndExited, .MouseMoved, .ActiveAlways], owner: self, userInfo: nil);
            self.addTrackingArea(self.contactTracker!);
        }
    }
    private func processMouse(location: CGFloat) {
        self._mouseIdx.modify { _ in Int(max(0, floor((location - self.allPadding - self.listPadding) / (self.tileSize.height + self.tilePadding)) - 1)) };
    }
    private func killMouse() {
        if let tracker = self.contactTracker { self.removeTrackingArea(tracker); }
        self.contactTracker = nil;
    }

    private func prepare() {
        let scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "mainview-scheduler");
        let latestMessage = self.connection.latestMessage;

        // draw new contacts as required.
        let tiles = self.connection.contacts.map({ (contacts) -> [ContactTile] in
            contacts.map { contact in self._contactTiles.get(contact, orElse: { self.drawContact(contact); }); };
        });

        // draw new conversations as required.
        self.connection.latestActivity.observeNext { contact in
            let conversation = contact.conversation;
            self._conversationViews.get(conversation.with, orElse: { self.drawConversation(conversation); })
        };

        // remember the latest foreign message.
        var latestForeignMessage_: Message?; // sort of a deviation from pattern. but i think it's better?
        let latestForeignMessage = latestMessage.filter({ message in message.isForeign() });
        latestForeignMessage.observeNext { message in latestForeignMessage_ = message };

        // calculate the correct sort (and implicitly visibility) of all contacts.
        let sort = self.connection.contacts
            .combineWithDefault(latestMessage.downcastToOptional(), defaultValue: nil).map({ contacts, _ in contacts })
            .combineWithDefault(self._statusTile.searchText, defaultValue: "")
            .map({ contacts, search -> [ Contact : Int ] in
                let (chattedContacts, restContacts) = contacts.part({ contact in contact.conversation.messages.count > 0 });

                let sortedChattedContacts = chattedContacts.sort({ a, b in
                    a.conversation.messages.first!.at.compare(b.conversation.messages.first!.at) == .OrderedDescending
                });

                let availableContacts = restContacts.filter { contact in contact.online_ && contact.presence_ == nil };
                let awayContacts = restContacts.filter { contact in contact.online_ && contact.presence_ != nil };

                var sorted: [Contact]; // HACK: mutable. gross.

                if search == "" {
                    sorted = sortedChattedContacts + availableContacts + awayContacts;
                } else {
                    let offlineContacts = restContacts.filter { contact in !contact.online_ };
                    let scores = (sortedChattedContacts + availableContacts + awayContacts + offlineContacts).map { contact in
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
        var lastInactive = NSDate.distantPast();
        self._state = GlobalInteraction.sharedInstance.keyPress
            .combineLatestWith(sort)
            .combineWithDefault(self._statusTile.searchText, defaultValue: "").map({ ($0.0, $0.1, $1); })
            .scan(.Inactive, { (last, args) -> MainState in
                let (wrappedKey, sort, search) = args;

                let key = keyTracker.extract(wrappedKey);
                switch (last, key) {
                case (_, .Blur): return .Inactive;

                // AOEU

                case (.Normal, .Escape): return .Inactive;
                case (.Normal, .Up): return .Selecting(0);

                case (.Selecting(0), .Down): return .Normal;
                case (let .Selecting(idx), .Down): return .Selecting(idx - 1);
                case (let .Selecting(idx), .Up): return .Selecting((idx + 1 == sort.count) ? idx : idx + 1);
                case (let .Selecting(idx), .Return): return .Chatting(sort.filter({ _, sidx in idx == sidx }).first!.0, last);
                case (.Selecting, .Escape): return .Normal;

                case (let .Searching(text, 0), .Down): return .Searching(text, 0);
                case (let .Searching(text, idx), .Down): return .Searching(text, idx - 1);
                case (let .Searching(text, idx), .Up): return .Searching(text, (idx + 1 == sort.count) ? idx : idx + 1);
                case (let .Searching(_, idx), .Return): return .Chatting(sort.filter({ _, sidx in idx == sidx }).first!.0, last);
                case (.Searching, .Escape): return .Normal;

                case (let .Chatting(_, previous), .Escape): return previous;

                case (.Inactive, .Focus): fallthrough;
                case (.Inactive, .GlobalToggle):
                    let now = NSDate();
                    let (state, time) = lastState;
                    let shouldRestore = time.dateByAddingTimeInterval(self.restoreInterval).isGreaterThan(now)

                    if let message = latestForeignMessage_ {
                        if message.at.isGreaterThan(lastInactive) && message.at.dateByAddingTimeInterval(self.messageShown).isGreaterThan(now) {
                            switch (shouldRestore, state) {
                            case (true, let .Chatting(_, previous)): return .Chatting(message.conversation.with, previous);
                            case (true, .Searching(_, _)): return .Chatting(message.conversation.with, .Normal);
                            case (true, let previous): return .Chatting(message.conversation.with, previous);
                            case (false, _): return .Chatting(message.conversation.with, .Normal);
                            }
                        }
                    }

                    if shouldRestore { return state; }
                    return .Normal;
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

        // keep track of our last state:
        self.state.filter({ state in state != .Inactive }).observeNext({ state in lastState = (state, NSDate()); });
        self.state.observeNext { state in self.state_ = state };

        // keep track of our last dismissal:
        self.state.skipRepeats({ $0 == $1 }).filter({ state in state == .Inactive }).observeNext({ _ in lastInactive = NSDate() });

        // wire/dewire mouse depending on our state:
        self.state.skipRepeats({ $0 == $1 }).observeNext { state in
            if state == .Inactive { self.killMouse(); }
            else                  { self.liveMouse(); }
        };

        // figure out which contacts currently have notification bubbles.
        let notifying = latestForeignMessage.always(0)
            .merge(latestForeignMessage.always(0).delay(self.messageShown, onScheduler: scheduler))
            .merge(self.state.always(0))
            .map { _ -> Set<Contact> in
                var result = Set<Contact>();
                let now = NSDate();

                // MAYBE HACK: i *think* we don't actually need to react based on mute, just readonce it.
                if !self.mutedMode_ {
                    // conversation states have changed. let's look at which have recent messages since the last dismissal.
                    for conversationView in self._conversationViews.all() {
                        let conversation = conversationView.conversation;
                        if let message = conversation.messages.find({ message in message.isForeign() }) {
                            if message.at.isGreaterThanOrEqualTo(lastInactive) && message.at.dateByAddingTimeInterval(self.messageShown).isGreaterThanOrEqualTo(now) {
                                result.insert(conversation.with);
                            }
                        }
                    }
                }

                return result;
            };

        // relayout as required.
        sort.combineLatestWith(tiles).map { order, _ in order } // (Order)
            .combineWithDefault(latestMessage.map({ _ in nil as AnyObject? }), defaultValue: nil).map { order, _ in order } // (Order)
            .combineWithDefault(self.state, defaultValue: .Inactive) // (Order, MainState)
            .combineWithDefault(notifying, defaultValue: Set<Contact>()) // ((Order, MainState), Set[Contact])
            .combineWithDefault(self.hiddenMode, defaultValue: false) // (((Order, MainState), Set[Contact]), Bool)
            .combineWithDefault(self.mouseIdx, defaultValue: nil) // ((((Order, MainState), Set[Contact]), Bool), Int?)
            .map({ tuple, mouseIdx in LayoutState(order: tuple.0.0.0, state: tuple.0.0.1, notifying: tuple.0.1, hidden: tuple.1, mouseIdx: mouseIdx); })
            .debounce(NSTimeInterval(0.02), onScheduler: QueueScheduler.mainQueueScheduler)
            .combinePrevious(LayoutState(order: [:], state: .Inactive, notifying: Set<Contact>(), hidden: false, mouseIdx: nil))
            .observeNext { last, this in self.relayout(last, this) };

        // show or hide contact labels as appropriate.
        tiles.combineLatestWith(sort) // ([ContactTile], [Contact:Int])
            .combineWithDefault(notifying.downcastToOptional(), defaultValue: nil) // (([ContactTile], [Contact:Int]), Set<Contact>?)
            .combineWithDefault(self.state, defaultValue: .Inactive) // ((([ContactTile], [Contact:Int]), Set<Contact>?), Contact?)
            .combineWithDefault(self.mouseIdx, defaultValue: nil) // (((([ContactTile], [Contact:Int]), Set<Contact>?), Contact?), Int?)
            .map({ ($0.0.0.0, $0.0.0.1, $0.0.1, $0.1, $1) }) // ([ContactTile], [Contact:Int], Set<Contact>?, Contact?)
            .observeNext { (tiles, sort, notifying, state, mouseIdx) in
                for tile in tiles {
                    tile.showLabel_ = ((state != .Inactive) || (mouseIdx != nil)) && (state.essentially != .Chatting) &&
                                      (notifying == nil || notifying!.count == 0) && (sort[tile.contact] != nil);
                }
            };

        // set contact select ring as appropriate. TODO: fix this awful reverse lookup everywhere.
        sort.combineWithDefault(self.state, defaultValue: .Inactive)
            .combineWithDefault(self.mouseIdx, defaultValue: nil).map({ ($0.0, $0.1, $1) })
            .map({ (sort, state, mouseIdx) -> Contact? in
                if let idx = mouseIdx { return sort.filter({ _, sidx in idx == sidx }).first!.0; }

                switch state {
                case let .Selecting(idx):       return sort.filter({ _, sidx in idx == sidx }).first!.0;
                case let .Searching(_, idx):    return sort.filter({ _, sidx in idx == sidx }).first!.0;
                default:                        return nil;
                }
            })
            .skipRepeats({ a, b in a == b })
            .combinePrevious(nil)
            .observeNext { last, this in
                if let tile = self._contactTiles.get(last) { tile.selected_ = false; }
                if let tile = self._contactTiles.get(this) { tile.selected_ = true; }
            };

        // render only the conversation for the active contact.
        self.state
            .combineLatestWith(sort)
            .map({ (state, sort) -> Contact? in
                switch state {
                case let .Chatting(with, _): return with;
                default: return nil;
                }
            })
            .combinePrevious(nil)
            .observeNext { (last, this) in
                if last == this { return; }
                if let view = self._conversationViews.get(last) { view.deactivate(); }

                if let contact = this { self._conversationViews.get(contact, orElse: { self.drawConversation(contact.conversation) }).activate(); }
            };

        // upon activate/deactivate, handle window focus and mouse events correctly.
        self.state.combinePrevious(.Inactive).observeNext { last, this in
            if last == .Inactive && this != .Inactive {
                NSApplication.sharedApplication().activateIgnoringOtherApps(true);
                self.window!.ignoresMouseEvents = false;
            } else if last != .Inactive && this == .Inactive {
                GlobalInteraction.sharedInstance.relinquish();
                self.window!.ignoresMouseEvents = true;
            }
        };
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
            conversation: conversation,
            mainView: self
        );
        self._contactTiles.get(conversation.with)!.attachConversation(newView);
        dispatch_async(dispatch_get_main_queue(), { self.addSubview(newView); });
        return newView;
    }

    private func relayout(lastState: LayoutState, _ thisState: LayoutState) {
        dispatch_async(dispatch_get_main_queue(), {
            // deal with self
            let tile = self._statusTile;
            let x = self.frame.width - self.tileSize.width - self.tilePadding;
            let y = self.allPadding;

            animationWithDuration(thisState.state.active ? 0.03 : 0.2, {
                if (thisState.state.active || thisState.mouseIdx != nil) { tile.animator().frame.origin = NSPoint(x: x, y: y); }
                else if (thisState.hidden) { tile.animator().frame.origin = NSPoint(x: x + self.tileSize.height + self.tilePadding, y: y); }
                else                       { tile.animator().frame.origin = NSPoint(x: x + (self.tileSize.height * 0.55), y: y); }
            });

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

                let yLast = self.allPadding + self.listPadding + ((self.tileSize.height + self.tilePadding) * CGFloat((last ?? 0) + 1));
                let yThis = self.allPadding + self.listPadding + ((self.tileSize.height + self.tilePadding) * CGFloat((this ?? 0) + 1));

                // TODO: repetitive.
                switch (last, lastState.notifying.contains(tile.contact), lastState.state, lastState.mouseIdx) {
                case (nil, _, _, _):                                                from = NSPoint(x: xOff, y: yThis);
                case (let lidx, _, let .Selecting(idx), _) where lidx == idx:       from = NSPoint(x: xOn, y: yLast);
                case (let lidx, _, let .Searching(_, idx), _) where lidx == idx:    from = NSPoint(x: xOn, y: yLast);
                case (_, _, let .Chatting(with, _), _) where with == tile.contact:  from = NSPoint(x: xOn, y: yLast);
                case (_, _, .Normal, _), (_, true, _, _):                           from = NSPoint(x: xOn, y: yLast);
                case (_, _, .Inactive, .Some(_)):                                   from = NSPoint(x: xOn, y: yLast);
                default: switch (lastState.state == .Inactive, lastState.hidden) {
                    case (true, true):                                              from = NSPoint(x: xOff, y: yLast);
                    default:                                                        from = NSPoint(x: xHalf, y: yLast);
                }}

                switch (this, thisState.notifying.contains(tile.contact), thisState.state, thisState.mouseIdx) {
                case (nil, _, _, _):                                                to = NSPoint(x: xOff, y: yLast);
                case (let tidx, _, let .Selecting(idx), _) where tidx == idx:       to = NSPoint(x: xOn, y: yThis);
                case (let tidx, _, let .Searching(_, idx), _) where tidx == idx:    to = NSPoint(x: xOn, y: yThis);
                case (_, _, let .Chatting(with, _), _) where with == tile.contact:  to = NSPoint(x: xOn, y: yThis);
                case (_, _, .Normal, _), (_, true, _, _):                           to = NSPoint(x: xOn, y: yThis);
                case (_, _, .Inactive, .Some(_)):                                   to = NSPoint(x: xOn, y: yThis);
                default: switch (thisState.state == .Inactive, thisState.hidden) {
                    case (true, true):                                              to = NSPoint(x: xOff, y: yThis);
                    default:                                                        to = NSPoint(x: xHalf, y: yThis);
                }}

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
                    conversationView.animator().frame.origin = NSPoint(
                        x: self.frame.width - self.tileSize.height - self.tilePadding - self.conversationPadding - self.conversationWidth,
                        y: yThis + self.conversationVOffset
                    );
                    conversationView.animator().frame.size = NSSize(
                        width: self.conversationWidth,
                        height: self.frame.height - (yThis + self.conversationVOffset)
                    );
                }
            }
        });
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
