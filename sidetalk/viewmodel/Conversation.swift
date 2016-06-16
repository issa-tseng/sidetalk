
import Foundation
import XMPPFramework
import ReactiveCocoa
import enum Result.NoError

struct Message {
    let from: Contact;
    let body: String;
    let at: NSDate;
}

enum ChatState {
    case Inactive, Active, Composing, Paused;

    static func fromMessage(it: XMPPMessage) -> ChatState? {
        if it.hasInactiveChatState() { return .Inactive; }
        if it.hasActiveChatState() { return .Active; }
        if it.hasComposingChatState() { return .Composing; }
        if it.hasPausedChatState() { return .Paused; }
        return nil;
    }
}

class Conversation: Hashable {
    let with: Contact;

    private var _messages = [Message]();

    var hashValue: Int { get { return self.with.hashValue; } };

    private let _latestMessageSignal = ManagedSignal<Message>();
    var latestMessage: Signal<Message, NoError> { get { return self._latestMessageSignal.signal; } };

    private let _chatStateSignal = ManagedSignal<ChatState>();
    var chatState: Signal<ChatState, NoError> { get { return self._chatStateSignal.signal; } };

    init(_ with: Contact) {
        self.with = with;
    }

    func addMessage(message: Message) {
        self._messages.append(message);
        self._latestMessageSignal.observer.sendNext(message);
    }

    func messages(range: NSRange) -> [Message] {
        if range.location > self._messages.count {
            return [];
        } else {
            return Array(self._messages[range.location..<min(range.length, self._messages.count)]);
        }
    }

    func setChatState(state: ChatState) {
        self._chatStateSignal.observer.sendNext(state);
    }
}

// base equality on Contact (which is based on JID). TODO: this is probably an awful idea.
func ==(lhs: Conversation, rhs: Conversation) -> Bool {
    return lhs.with == rhs.with;
}
