
import Foundation
import XMPPFramework
import ReactiveCocoa
import enum Result.NoError

struct Message {
    let from: Contact;
    let body: String;
    let at: Date;
    let conversation: Conversation;

    func isForeign() -> Bool { return self.from == self.conversation.with; }
}

enum ChatState {
    case inactive, active, composing, paused;

    static func fromMessage(_ it: XMPPMessage) -> ChatState? {
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

    fileprivate let _latestMessageSignal = ManagedSignal<Message>();
    var latestMessage: Signal<Message, NoError> { get { return self._latestMessageSignal.signal; } };

    fileprivate let _chatStateSignal = ManagedSignal<ChatState>();
    var chatState: Signal<ChatState, NoError> { get { return self._chatStateSignal.signal; } };

    init(_ with: Contact, connection: Connection) {
        self.with = with;
        self.connection = connection;
    }

    func addMessage(_ message: Message) {
        self.messages.insert(message, at: 0);
        self._latestMessageSignal.observer.sendNext(message);
    }

    func sendMessage(_ text: String) {
        self.connection.sendMessage(self.with, text);
    }

    func messages(_ range: NSRange) -> [Message] {
        if range.location > self.messages.count {
            return [];
        } else {
            return Array(self.messages[range.location..<min(range.length, self.messages.count)]);
        }
    }

    func setChatState(_ state: ChatState) {
        self._chatStateSignal.observer.sendNext(state);
    }

    func sendChatState(_ state: ChatState) {
        self.connection.sendChatState(self.with, state);
    }
}

// base equality on Contact (which is based on JID). TODO: this is probably an awful idea.
func ==(lhs: Conversation, rhs: Conversation) -> Bool {
    return lhs.with == rhs.with;
}
