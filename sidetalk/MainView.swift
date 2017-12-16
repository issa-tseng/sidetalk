
import Foundation;
import Cocoa;
import ReactiveSwift;
import FuzzySearch;
import enum Result.NoError;

struct LayoutState {
    let order: SortOf<Contact>;
    let state: MainState;
    let notifying: Set<Contact>;
    let hidden: Bool;
    let mouseIdx: Int?;
}

enum MouseButton: Impulsable {
    case None;
    case Left(event: NSEvent);
    case Right(event: NSEvent);

    static func noopValue() -> MouseButton { return .None; }
}

class STScrollView: NSScrollView {
    var onScroll: (() -> ())?;
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event);
        self.onScroll?();
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true; }
}

// TODO: split into V/VM?
class MainView: NSView {
    internal let connection: Connection;

    private let gradientView = GradientView();
    private let _statusTile: StatusTile;
    private let modeView: ModeView;
    private var _contactTiles = QuickCache<Contact, ContactTile>();
    private var _conversationViews = QuickCache<Contact, ConversationView>();

    private let scrollView = STScrollView();
    private let scrollContents = NSView();
    private var scrollHeightConstraint: NSLayoutConstraint?;

    private var marginTracker: NSTrackingArea?;
    private var notifyingTracker: NSTrackingArea?;
    private var contactTracker: NSTrackingArea?;

    private var wantsMouseMain = MutableProperty<Bool>(false);
    private var wantsMouseNotifying = MutableProperty<Bool>(false);
    private var wantsMouseConversation = MutableProperty<Bool>(false);

    private var _state = MutableProperty<MainState>(.Inactive);
    private var state_: MainState { get { return self._state.value; } };
    var state: Signal<MainState, NoError> { get { return self._state.signal; } };

    private var _lastInactive = MutableProperty<Date>(Date.distantPast);
    private var lastInactive_: Date { get { return self._lastInactive.value; } };
    private var lastInactive: Signal<Date, NoError> { get { return self._lastInactive.signal; } };

    private let _mouseIdx = MutableProperty<Int?>(nil);
    var mouseIdx_: Int? { get { return self._mouseIdx.value; } };
    var mouseIdx: Signal<Int?, NoError> { get { return self._mouseIdx.signal.skipRepeats({ a, b in a == b }); } };

    private let _mouseClickGenerator = Impulse.generate(MouseButton.self);
    private let _mouseClickSignal = ManagedSignal<Impulse<MouseButton>>();
    var mouseClick: Signal<Impulse<MouseButton>, NoError> { get { return self._mouseClickSignal.signal; } };

    private let _hiddenMode = MutableProperty<Bool>(false);
    var hiddenMode: Signal<Bool, NoError> { get { return self._hiddenMode.signal; } };

    private let _mutedMode = MutableProperty<Bool>(false);
    var mutedMode: Signal<Bool, NoError> { get { return self._mutedMode.signal; } };
    var mutedMode_: Bool { get { return self._mutedMode.value; } };

    let starredJids: Registry;
    let hiddenJids: Registry;

    // drawing ks. should these go elsewhere?
    let allPadding = CGFloat(12);
    let listPadding = CGFloat(73);
    let tileSize = NSSize(width: 300, height: 50);
    let tilePadding = CGFloat(4);
    let conversationPadding = CGFloat(14);
    let conversationWidth = CGFloat(300);
    let conversationVOffset = CGFloat(-72);

    let messageShown = TimeInterval(5.0);
    let restoreInterval = TimeInterval(10.0 * 60.0);
    let inactivityInterval = TimeInterval(5.0 * 24.0 * 60.0 * 60.0);

    private let _pressedKey = ManagedSignal<Key>();

    init(frame: CGRect, connection: Connection, starred: Registry, hidden: Registry) {
        // store and init.
        self.connection = connection;
        self.starredJids = starred;
        self.hiddenJids = hidden;
        self._statusTile = StatusTile(connection: connection, frame: NSRect(origin: NSPoint.zero, size: frame.size));
        self.modeView = ModeView(frame: NSRect(origin: NSPoint(x: frame.width - ST.mode.marginRight - ST.mode.iconSize, y: ST.mode.marginBottom),
                                               size: NSSize(width: ST.mode.iconSize, height: ST.mode.iconSize * 2)));

        super.init(frame: frame);

        // background gradient initial state and addition.
        self.gradientView.translatesAutoresizingMaskIntoConstraints = false;
        self.gradientView.alphaValue = 0;
        self.addSubview(self.gradientView);
        self.addConstraints([
            self.gradientView.constrain.left == self.constrain.left, self.gradientView.constrain.right == self.constrain.right,
            self.gradientView.constrain.top == self.constrain.top, self.gradientView.constrain.bottom == self.constrain.bottom
        ]);

        // status tile initial positioning.
        self.addSubview(self._statusTile);
        self._statusTile.frame.origin = NSPoint(
            x: frame.width - self.tileSize.width - self.tilePadding + (self.tileSize.height * 0.55),
            y: self.allPadding
        );
        self.addSubview(self.modeView);

        // scrollview basic properties and positioning.
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false;
        self.scrollView.hasVerticalScroller = true;
        self.scrollView.drawsBackground = false;
        self.scrollView.horizontalScrollElasticity = .none;
        self.addSubview(self.scrollView);

        self.scrollView.onScroll = { self.scrolled(); };

        self.addConstraints([
            self.scrollView.constrain.bottom == self.constrain.bottom - (self.allPadding + self.listPadding + self.tileSize.height + self.tilePadding),
            self.scrollView.constrain.right == self.constrain.right + 30,
            self.scrollView.constrain.top == self.constrain.top, self.scrollView.constrain.left == self.constrain.left
        ]);

        // scrollcontents basic properties.
        self.scrollContents.translatesAutoresizingMaskIntoConstraints = false;
        self.scrollContents.frame = self.scrollView.contentView.bounds;
        self.scrollView.documentView = self.scrollContents;
        self.scrollView.addConstraints([
            self.scrollContents.constrain.left == self.scrollView.constrain.left,
            self.scrollContents.constrain.right == self.scrollView.constrain.right - 30,
            self.scrollContents.constrain.bottom == self.scrollView.constrain.bottom
        ]);

        // set up prepares.
        self.prepare();
        self._statusTile.prepare(self);
        self.modeView.prepare(self);

        // poke some signals.
        self.starredJids.ping();
        self.hiddenJids.ping();

        // mouse things.
        self.marginTracker = NSTrackingArea(rect: NSRect(origin: NSPoint(x: frame.width - 2, y: 0), size: frame.size),
                                            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil);
        self.addTrackingArea(self.marginTracker!);
    }

    func setHide(_ hidden: Bool) { self._hiddenMode.modify({ _ in hidden }); }
    func setMute(_ muted: Bool) { self._mutedMode.modify({ _ in muted }); }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea == self.marginTracker {
            self.liveMouse();
            self._mouseIdx.modify({ _ in self.idxForMouse(event.locationInWindow.y) });
        }
    }
    override func mouseMoved(with event: NSEvent) {
        if let tracker = self.contactTracker {
            if event.locationInWindow.x > tracker.rect.minX {
                self._mouseIdx.modify({ _ in self.idxForMouse(event.locationInWindow.y) });
                self.wantsMouseMain.modify({ _ in true });
            }
        } else if let tracker = self.notifyingTracker {
            guard let notifyingIdx = tracker.userInfo?["notifying"] as? Set<Int> else { return; }
            let idx = self.idxForMouse(event.locationInWindow.y);
            self.wantsMouseNotifying.modify({ _ in notifyingIdx.contains(idx) });
        }
    }
    override func mouseExited(with event: NSEvent) {
        if event.trackingArea == self.contactTracker {
            if self.state_ == .Inactive { self.killMouse(); }
            self._mouseIdx.modify({ _ -> Int? in nil });
        }

        if event.trackingArea != self.marginTracker {
            self.wantsMouseMain.modify({ _ in false });
            self.wantsMouseNotifying.modify({ _ in false });
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true; }
    override func mouseDown(with event: NSEvent) {
        //self._mouseClickSignal.observer.sendNext(self._mouseClickGenerator.create(.Left(event: theEvent)));
        if self.mouseIdx_ != nil {
            GlobalInteraction.sharedInstance.send(.Click);
        } else if let tracker = self.notifyingTracker {
            // only process the notifying tracker on mousedown so we don't pop the whole frame.
            guard let notifyingIdx = tracker.userInfo?["notifying"] as? Set<Int> else { return; }
            let idx = self.idxForMouse(event.locationInWindow.y);
            if notifyingIdx.contains(idx) {
                self._mouseIdx.modify { _ in idx };
                GlobalInteraction.sharedInstance.send(.Click);
            }
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        self._mouseClickSignal.observer.send(value: self._mouseClickGenerator.create(.Right(event: event)));
    }

    private func liveMouse() {
        if self.contactTracker == nil {
            self.contactTracker = NSTrackingArea(rect: NSRect(origin: NSPoint(x: frame.width - self.tileSize.height - self.tilePadding, y: 0), size: frame.size),
                                                 options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: nil);
            self.addTrackingArea(self.contactTracker!);
        }
    }
    private func idxForMouse(_ location: CGFloat) -> Int {
        return Int(max(0, floor((location + self.scrollView.contentView.documentVisibleRect.origin.y - self.allPadding - self.listPadding) / (self.tileSize.height + self.tilePadding)) - 1)); // TODO/HACK: why -1?
    }
    private func killMouse() {
        if let tracker = self.contactTracker { self.removeTrackingArea(tracker); }
        self.contactTracker = nil;
        self._mouseIdx.modify({ _ -> Int? in nil }); // unlike liveMouse, we always want to modify the idx, because it's an active flag of sorts.
        self.wantsMouseMain.modify({ _ in false });
    }

    @objc private func scrolled() {
        if self.state_.essentially == .Chatting { GlobalInteraction.sharedInstance.send(.Escape); } // HACK: feels like a sloppy way to do this.
        self._mouseIdx.modify { _ in self.idxForMouse(NSEvent.mouseLocation.y) };
    }

    // don't react to mouse clicks unless the pointer is in a relevant spot at a relevant time.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // normal mouse behaviour any time we're within a conversation view.
        if let view = super.hitTest(point) {
            if view.ancestors().find({ view in (view as? ConversationView) != nil }) != nil {
                return view;
            }
        }

        // otherwise always return scrollview if we have a hit, so that subsequent calls (click, mousewheel) go to the right place.
        if self.mouseIdx_ != nil {
            return self.scrollView;
        } else if let tracker = self.notifyingTracker {
            // TODO/HACK: repetitive from mouseDown.
            guard let notifyingIdx = tracker.userInfo?["notifying"] as? Set<Int> else { return nil; }
            if notifyingIdx.contains(self.idxForMouse(point.y)) { return self.scrollView; }
        }

        return nil;
    }

    private func prepare() {
        let scheduler = QueueScheduler(qos: .default, name: "mainview-scheduler");
        let latestMessage = self.connection.latestMessage;
        var lastState: (MainState, Date) = (.Normal, Date());

        // draw new contacts as required.
        let tiles = self.connection.contacts.map({ (contacts) -> [ContactTile] in
            contacts.map { contact in self._contactTiles.get(contact, orElse: { self.drawContact(contact); }); };
        });

        // draw new conversations as required.
        self.connection.latestActivity.observeValues { contact in
            let conversation = contact.conversation;
            self._conversationViews.get(conversation.with, orElse: { self.drawConversation(conversation); });
        };

        // remember the latest foreign message.
        var latestForeignMessage_: Message?; // sort of a deviation from pattern. but i think it's better?
        let latestForeignMessage = latestMessage.filter({ message in message.isForeign() });
        latestForeignMessage.observeValues { message in latestForeignMessage_ = message };

        // figure out which contacts currently have notification bubbles.
        let notifying = latestForeignMessage.always(value: 0)
            .merge(latestForeignMessage.always(value: 0).delay(self.messageShown, on: scheduler))
            .merge(self.lastInactive.always(value: 0))
            .map { _ -> Set<Contact> in
                var result = Set<Contact>();
                let now = Date();

                // MAYBE HACK: i *think* we don't actually need to react based on mute, just readonce it.
                if !self.mutedMode_ {
                    // conversation states have changed. let's look at which have recent messages since the last dismissal.
                    for conversationView in self._conversationViews.all() {
                        let conversation = conversationView.conversation;
                        if let message = conversation.messages.find({ message in message.isForeign() }) {
                            if (message.at >= self.lastInactive_) && (message.at.addingTimeInterval(self.messageShown) >= now) {
                                result.insert(conversation.with);
                            }
                        }
                    }
                }

                return result;
            };

        // calculate the correct sort (and implicitly visibility) of all contacts.
        let sort = self.connection.contacts
            .combineWithDefault(latestMessage.downcastToOptional(), defaultValue: nil).map({ contacts, _ in contacts })
            .combineWithDefault(self._statusTile.searchText, defaultValue: "")
            .combineWithDefault(notifying, defaultValue: Set<Contact>())
            .combineWithDefault(self.starredJids.members, defaultValue: Set<String>())
            .combineWithDefault(self.hiddenJids.members, defaultValue: Set<String>()).map({ ($0.0.0.0, $0.0.0.1, $0.0.1, $0.1, $1) })
            .map({ contacts, search, notifying, starred, hidden -> SortOf<Contact> in
                let filteredContacts = contacts.filter({ contact in !hidden.contains(contact.inner.jid().full()) });
                let (starredContacts, plebContacts) = filteredContacts.part({ contact in starred.contains(contact.inner.jid().full()) });

                let cutoff = Date().addingTimeInterval(-1.0 * self.inactivityInterval);
                let (chattedContacts, restContacts) = plebContacts.part({ contact in
                    contact.conversation.messages.contains(where: { message in message.at >= cutoff })
                });

                let sortedChattedContacts = chattedContacts.sorted(by: { a, b in
                    a.conversation.messages.first!.at.compare(b.conversation.messages.first!.at) == .orderedDescending
                });

                let availableContacts = restContacts.filter { contact in contact.online_ && contact.presence_ == nil };
                let awayContacts = restContacts.filter { contact in contact.online_ && contact.presence_ != nil };

                var sorted: [Contact]; // HACK: mutable. gross.

                if search == "" {
                    sorted = starredContacts + sortedChattedContacts + availableContacts + awayContacts;
                } else {
                    let offlineContacts = restContacts.filter { contact in !contact.online_ };
                    let scores = (sortedChattedContacts + availableContacts + awayContacts + offlineContacts).map { contact in
                        (contact, FuzzySearch.score(originalString: contact.displayName, stringToMatch: search, fuzziness: 0.75));
                    };

                    let maxScore = scores.map({ (_, score) in score }).max();
                    let matches = scores.filter({ (_, score) in score > maxScore! - 0.2 && score > 0.1 }).map({ (contact, _) in contact });

                    let notifyingOverrides = sortedChattedContacts.filter({ contact in notifying.contains(contact) });
                    sorted = notifyingOverrides + matches.filter({ contact in !notifying.contains(contact) });
                }

                return SortOf(sorted);
            });

        // determine global state (gets pushed into MainState._state at the end).
        let keyTracker = Impulse.track(Key.self);
        GlobalInteraction.sharedInstance.keyPress
            .combineLatest(with: sort)
            .combineWithDefault(self._statusTile.searchText, defaultValue: "").map({ ($0.0, $0.1, $1); })
            .scan(.Inactive, { (last, args) -> MainState in
                let (wrappedKey, sort, search) = args;

                let key = keyTracker.extract(wrappedKey);
                let mousedUser = sort[Clamped(self.mouseIdx_)];
                switch (last, key) {
                case (_, .Blur): return .Inactive;

                case (let .Chatting(with, previous), .Click) where with == mousedUser: return previous;
                case (let .Chatting(_, previous), .Click) where mousedUser != nil: return .Chatting(mousedUser!, previous);
                case (_, .Click) where mousedUser != nil: return .Chatting(mousedUser!, .Normal);

                case (.Normal, .Escape): return .Inactive;
                case (.Normal, .Up): return .Selecting(0);

                case (.Selecting(0), .Down): return .Normal;
                case (let .Selecting(idx), .Down): return .Selecting(idx - 1);
                case (let .Selecting(idx), .Up): return .Selecting((idx + 1 == sort.count) ? idx : idx + 1);
                case (let .Selecting(idx), .Return) where sort[Clamped(idx)] != nil: return .Chatting(sort[Clamped(idx)]!, last);
                case (.Selecting, .Escape): return .Normal;

                case (let .Searching(text, 0), .Down): return .Searching(text, 0);
                case (let .Searching(text, idx), .Down): return .Searching(text, idx - 1);
                case (let .Searching(text, idx), .Up): return .Searching(text, (idx + 1 == sort.count) ? idx : idx + 1);
                case (let .Searching(text, idx), .Return):
                    if let contact = sort[Clamped(idx)] {
                        return .Chatting(contact, last);
                    } else {
                        return .Searching(text, idx);
                    }
                case (.Searching, .Escape): return .Normal;

                case (let .Chatting(with, .Selecting(_)), .Escape): return .Selecting(sort[with]!);
                case (.Chatting(_, .Searching(_, _)), .Escape): return .Normal;
                case (let .Chatting(_, previous), .Escape): return previous;

                case (.Inactive, .Focus): fallthrough;
                case (.Inactive, .GlobalToggle):
                    let now = Date();
                    let (state, time) = lastState;
                    let shouldRestore = time.addingTimeInterval(self.restoreInterval) > now;

                    if let message = latestForeignMessage_ {
                        if (message.at > self.lastInactive_) && (message.at.addingTimeInterval(self.messageShown) > now) {
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
            })
            .observeValues({ state in self._state.modify({ _ -> MainState in state }) });

        // keep track of our last state:
        self.state.filter({ state in state != .Inactive }).observeValues({ state in lastState = (state, Date()); });

        // keep track of our last dismissal:
        self.state.skipRepeats({ $0 == $1 }).filter({ state in state == .Inactive }).observeValues({ _ in
            DispatchQueue.global(qos: .default).async(execute: { self._lastInactive.modify({ _ in Date() }) });
        });

        // wire/dewire mouse depending on our state:
        self.state.map({ $0 == .Inactive }).skipRepeats().observeValues { inactive in
            DispatchQueue.main.async(execute: { if inactive { self.killMouse(); } else { self.liveMouse(); } });
        };

        // if there are any contacts currently notifying and we are inactive, create or update a tracking area.
        notifying
            .combineLatest(with: sort)
            .combineLatest(with: self.state).map({ ($0.0, $0.1, $1) })
            .observeValues { notifying, sort, state in
                if (notifying.count > 0) && (state == .Inactive) {
                    if let tracker = self.notifyingTracker { DispatchQueue.main.async(execute: { self.removeTrackingArea(tracker); }); }

                    let notifyingContacts = Set(notifying.filter({ contact in sort[contact] != nil }).map({ contact in sort[contact]! })); // TODO: cleaner upcast?
                    self.notifyingTracker = NSTrackingArea(rect: NSRect(origin: NSPoint(x: self.frame.width - self.tileSize.height - self.tilePadding, y: 0), size: self.frame.size),
                        options: [ .mouseEnteredAndExited, .mouseMoved, .activeAlways ], owner: self, userInfo: [ "notifying": notifyingContacts ]);
                    DispatchQueue.main.async(execute: { self.addTrackingArea(self.notifyingTracker!); });
                } else if let tracker = self.notifyingTracker {
                    DispatchQueue.main.async(execute: { self.removeTrackingArea(tracker); });
                }
            };

        // relayout as required.
        sort.combineLatest(with: tiles).map { order, _ in order } // (Order)
            .combineWithDefault(latestMessage.map({ _ in nil as AnyObject? }), defaultValue: nil).map { order, _ in order } // (Order)
            .combineWithDefault(self.state, defaultValue: .Inactive) // (Order, MainState)
            .combineWithDefault(notifying, defaultValue: Set<Contact>()) // ((Order, MainState), Set[Contact])
            .combineWithDefault(self.hiddenMode, defaultValue: false) // (((Order, MainState), Set[Contact]), Bool)
            .combineWithDefault(self.mouseIdx, defaultValue: nil) // ((((Order, MainState), Set[Contact]), Bool), Int?)
            .map({ tuple, mouseIdx in LayoutState(order: tuple.0.0.0, state: tuple.0.0.1, notifying: tuple.0.1, hidden: tuple.1, mouseIdx: mouseIdx); })
            .debounce(TimeInterval(0.02), on: QueueScheduler.main)
            .combinePrevious(LayoutState(order: SortOf<Contact>(), state: .Inactive, notifying: Set<Contact>(), hidden: false, mouseIdx: nil))
            .observeValues { states in self.relayout(states.0, states.1) };

        // show or hide contact labels as appropriate.
        tiles.combineLatest(with: sort) // ([ContactTile], [Contact:Int])
            .combineWithDefault(notifying.downcastToOptional(), defaultValue: nil) // (([ContactTile], [Contact:Int]), Set<Contact>?)
            .combineWithDefault(self.state, defaultValue: .Inactive) // ((([ContactTile], [Contact:Int]), Set<Contact>?), Contact?)
            .combineWithDefault(self.mouseIdx, defaultValue: nil) // (((([ContactTile], [Contact:Int]), Set<Contact>?), Contact?), Int?)
            .map({ ($0.0.0.0, $0.0.0.1, $0.0.1, $0.1, $1) }) // ([ContactTile], [Contact:Int], Set<Contact>?, Contact?)
            .observeValues { (tiles, sort, notifying, state, mouseIdx) in
                for tile in tiles {
                    tile.showLabel_ = ((state != .Inactive) || (mouseIdx != nil)) && (state.essentially != .Chatting) &&
                                      (notifying == nil || notifying!.count == 0) && (sort[tile.contact] != nil);
                }
            };

        // set contact select ring as appropriate.
        sort.combineWithDefault(self.state, defaultValue: .Inactive)
            .combineWithDefault(self.mouseIdx, defaultValue: nil).map({ ($0.0, $0.1, $1) })
            .map({ (sort, state, mouseIdx) -> Contact? in
                switch (state, mouseIdx) {
                case (let .Chatting(contact, _), let .some(idx)) where sort[contact] == idx: return nil;
                case (_, let .some(idx)):           return sort[Clamped(idx)];
                case (let .Selecting(idx), _):      return sort[Clamped(idx)];
                case (let .Searching(_, idx), _):   return sort[Clamped(idx)];
                default:                            return nil;
                }
            })
            .skipRepeats({ a, b in a == b })
            .combinePrevious(nil)
            .observeValues { last, this in
                if let tile = self._contactTiles.get(last) { tile.selected_ = false; }
                if let tile = self._contactTiles.get(this) { tile.selected_ = true; }
            };

        // set contact star visibility as appropriate.
        tiles.combineWithDefault(self.starredJids.members, defaultValue: Set<String>()).observeValues({ (tiles, starred) in
            for tile in tiles {
                tile.showStar_ = starred.contains(tile.contact.inner.jid().full());
            }
        });

        // determine who we're actively chatting with.
        let activeConversation = self.state
            .combineLatest(with: sort)
            .map({ (state, sort) -> Contact? in
                switch state {
                case let .Chatting(with, _): return with;
                default: return nil;
                }
            });

        // render only the conversation for the active contact.
        activeConversation
            .combinePrevious(nil)
            .observeValues { (last, this) in
                if last == this { return; }
                if let view = self._conversationViews.get(last) { view.deactivate(); }

                if let contact = this { self._conversationViews.get(contact, orElse: { self.drawConversation(contact.conversation) }).activate(); }
            };

        let hasConversation = activeConversation.map({ x in x != nil });

        // we want to trap mouse events if a conversation is open.
        hasConversation.observeValues({ isOpen in self.wantsMouseConversation.modify({ _ in isOpen }); });

        // also if a conversation is open we want to pop in the background gradient. TODO: animation seems to drop the framerate :/
        hasConversation.observeValues({ isOpen in DispatchQueue.main.async(execute: { self.gradientView.alphaValue = (isOpen ? 1.0 : 0); }) });

        // if a conversation is open, all other conversations go to compact mode for notifications.
        hasConversation.observeValues({ isOpen in for conversation in self._conversationViews.all() { conversation.displayMode_ = (isOpen ? .Compact : .Normal); } });

        // upon activate/deactivate, handle window focus correctly.
        self.state.combinePrevious(.Inactive).observeValues { last, this in
            if last == .Inactive && this != .Inactive {
                NSApplication.shared.activate(ignoringOtherApps: true);
            } else if last != .Inactive && this == .Inactive {
                GlobalInteraction.sharedInstance.relinquish();
            }
        };

        // if we have been idle and inactive for 10 seconds, revert scroll to the bottom.
        self.state.skipRepeats({ $0 == $1 }).filter({ state in state == .Inactive }).always(value: 0)
            .merge(self.mouseIdx.filter({ $0 == nil }).always(value: 0))
            .delay(ST.main.inactiveDelay, on: scheduler)
            .observeValues { _ in DispatchQueue.main.async(execute: {
                if (self.state_ == .Inactive) && (self.mouseIdx_ == nil) && (self.scrollView.contentView.documentVisibleRect.origin.y != 0) {
                    self.scrollView.contentView.animator().setBoundsOrigin(NSPoint.zero);
                }
             }); }

        // if anyone wants mouse events, give it to them.
        let (dummy, dummyObserver) = Signal<Bool, NoError>.pipe();
        dummy.combineWithDefault(self.wantsMouseMain.signal, defaultValue: false).map({ _, x in x })
            .combineWithDefault(self.wantsMouseNotifying.signal, defaultValue: false).map({ a, b in a || b })
            .combineWithDefault(self.wantsMouseConversation.signal, defaultValue: false).map({ a, b in a || b })
            .observeValues({ wantsMouse in self.window?.ignoresMouseEvents = !wantsMouse });
        dummyObserver.send(value: false);

        // show context menu on right-click on a contact.
        let buttonTracker = Impulse.track(MouseButton.self);
        sort.combineLatest(with: self.mouseClick)
            .combineLatest(with: self.mouseIdx).map({ ($0.0, $0.1, $1); })
            .observeValues({ (sort, buttonImpulse, idx) in
                let button = buttonTracker.extract(buttonImpulse);
                if case let .Right(event) = button {
                    if let contact = sort[idx] {
                        ContactMenu.show(contact, event: event, view: self);
                    }
                }
            });
    }

    private func drawContact(_ contact: Contact) -> ContactTile {
        let newTile = ContactTile(
            frame: NSRect(origin: NSPoint.zero, size: self.tileSize),
            contact: contact
        );
        newTile.showStar_ = self.starredJids.contains(member: contact.inner.jid().full());
        DispatchQueue.main.async(execute: { self.scrollContents.addSubview(newTile); });
        return newTile;
    }

    private func drawConversation(_ conversation: Conversation) -> ConversationView {
        let newView = ConversationView(
            frame: self.frame,
            width: self.conversationWidth,
            conversation: conversation,
            mainView: self
        );
        self._contactTiles.get(conversation.with)!.attachConversation(newView);
        DispatchQueue.main.async(execute: { self.addSubview(newView); });
        return newView;
    }

    private func relayout(_ lastState: LayoutState, _ thisState: LayoutState) {
        DispatchQueue.main.async(execute: {
            // deal with self
            let tile = self._statusTile;
            let x = self.frame.width - self.tileSize.width - self.tilePadding;
            let y = self.allPadding;

            animationWithDuration(duration: thisState.state.active ? 0.03 : 0.2, {
                if (thisState.state.active || thisState.mouseIdx != nil) { tile.animator().frame.origin = NSPoint(x: x, y: y); }
                else if (thisState.hidden) { tile.animator().frame.origin = NSPoint(x: x + self.tileSize.height + self.tilePadding, y: y); }
                else                       { tile.animator().frame.origin = NSPoint(x: x + (self.tileSize.height * 0.55), y: y); }
            });

            // deal with actual contacts
            for tile in self._contactTiles.all() {
                let last = lastState.order[tile.contact];
                let this = thisState.order[tile.contact];

                // make sure we're offscreen if we're not to be shown
                if last == nil && this == nil {
                    tile.isHidden = true;
                    continue;
                } else {
                    tile.isHidden = false;
                }

                // calculate positions. TODO: mutable. gross.
                var from: NSPoint;
                var to: NSPoint;

                let xOn = self.frame.width - self.tileSize.width - self.tilePadding;
                let xHalf = self.frame.width - self.tileSize.width + (self.tileSize.height * 0.55);
                let xOff = self.frame.width - self.tileSize.width + self.tileSize.height;

                let yLast = (self.tileSize.height + self.tilePadding) * CGFloat(last ?? 0);
                let yThis = (self.tileSize.height + self.tilePadding) * CGFloat(this ?? 0);

                // TODO: repetitive.
                switch (last, lastState.notifying.contains(tile.contact), lastState.state, lastState.mouseIdx) {
                case (nil, _, _, _):                                                from = NSPoint(x: xOff, y: yThis);
                case (let lidx, _, let .Selecting(idx), _) where lidx == idx:       from = NSPoint(x: xOn, y: yLast);
                case (let lidx, _, let .Searching(_, idx), _) where lidx == idx:    from = NSPoint(x: xOn, y: yLast);
                case (_, _, let .Chatting(with, _), _) where with == tile.contact:  from = NSPoint(x: xOn, y: yLast);
                case (_, _, .Normal, _), (_, true, _, _):                           from = NSPoint(x: xOn, y: yLast);
                case (_, _, .Inactive, .some(_)):                                   from = NSPoint(x: xOn, y: yLast);
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
                case (_, _, .Inactive, .some(_)):                                   to = NSPoint(x: xOn, y: yThis);
                default: switch (thisState.state == .Inactive, thisState.hidden) {
                    case (true, true):                                              to = NSPoint(x: xOff, y: yThis);
                    default:                                                        to = NSPoint(x: xHalf, y: yThis);
                }}

                // actually animate the tile. set its from directly, then after letting the layout settle set the to on the animator.
                tile.setFrameOrigin(from);
                let duration = TimeInterval((!lastState.state.active && thisState.state.active ? 0.05 : 0.2) + (0.02 * Double(this ?? 0)));
                DispatchQueue.main.async(execute: { animationWithDuration(duration: duration, { tile.animator().setFrameOrigin(to); }); });

                // if we have a conversation as well, position that appropriately.
                if let conversationView = self._conversationViews.get(tile.contact) {
                    var scrollY = self.scrollView.contentView.documentVisibleRect.origin.y; // TODO: gross; mutable.
                    // if the conversation is active and its contact is offscreen, we want to scroll the list.
                    if conversationView.active_ {
                        let frameHeight = self.scrollView.frame.height;
                        if (yThis < scrollY) || (yThis > (scrollY + frameHeight)) {
                            scrollY = (yThis < scrollY) ? yThis : floor(yThis - (frameHeight / 2));
                            self.scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: scrollY));
                        }
                    }

                    // position the conversation.
                    let y = self.allPadding + self.listPadding + self.tileSize.height + yThis + self.conversationVOffset - scrollY;
                    conversationView.animator().frame.origin = NSPoint(
                        x: self.frame.width - self.tileSize.height - self.tilePadding - self.conversationPadding - self.conversationWidth,
                        y: y
                    );
                    conversationView.animator().frame.size = NSSize(
                        width: self.conversationWidth,
                        height: max(ST.conversation.minHeight, self.frame.height - y)
                    );
                }
            }

            // deal with scroll height. make sure it's at least the full scroll height.
            if let constraint = self.scrollHeightConstraint { self.scrollView.removeConstraint(constraint); }
            let newHeight = max(self.scrollView.frame.height, CGFloat(thisState.order.count) * (self.tileSize.height + self.tilePadding));
            self.scrollHeightConstraint = (self.scrollContents.constrain.height == newHeight);
            self.scrollView.addConstraint(self.scrollHeightConstraint!);
        });
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        return event.keyCode == 53;
    }

    required init(coder: NSCoder) {
        fatalError("no coder");
    }
}
