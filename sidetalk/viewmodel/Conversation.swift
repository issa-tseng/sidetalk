
import Foundation
import XMPPFramework
import ReactiveCocoa
import enum Result.NoError

struct Message {
    let from: Contact;
    let body: String;
    let at: NSDate;
    let conversation: Conversation;
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
    let connection: Connection;

    var messages = [Message]();

    var hashValue: Int { get { return self.with.hashValue; } };

    private let _latestMessageSignal = ManagedSignal<Message>();
    var latestMessage: Signal<Message, NoError> { get { return self._latestMessageSignal.signal; } };

    private let _chatStateSignal = ManagedSignal<ChatState>();
    var chatState: Signal<ChatState, NoError> { get { return self._chatStateSignal.signal; } };

    init(_ with: Contact, connection: Connection) {
        self.with = with;
        self.connection = connection;
    }

    func addMessage(message: Message) {
        self.messages.insert(message, atIndex: 0);
        self._latestMessageSignal.observer.sendNext(message);
    }

    func sendMessage(text: String) {
        self.connection.sendMessage(self.with, text);
    }

    func messages(range: NSRange) -> [Message] {
        if range.location > self.messages.count {
            return [];
        } else {
            return Array(self.messages[range.location..<min(range.length, self.messages.count)]);
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
