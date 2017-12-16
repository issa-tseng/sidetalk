
import Foundation
import XMPPFramework
import ReactiveSwift
import enum Result.NoError

struct Message {
    let from: Contact;
    let body: String;
    let at: Date;
    let conversation: Conversation;

    func isForeign() -> Bool { return self.from == self.conversation.with; }
}

enum ChatState {
    case Inactive, Active, Composing, Paused;

    static func from(_ message: XMPPMessage) -> ChatState? {
        if message.hasInactiveChatState() { return .Inactive; }
        if message.hasActiveChatState() { return .Active; }
        if message.hasComposingChatState() { return .Composing; }
        if message.hasPausedChatState() { return .Paused; }
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

    func addMessage(_ message: Message) {
        self.messages.insert(message, at: 0);
        self._latestMessageSignal.observer.send(value: message);
    }

    func sendMessage(_ text: String) {
        self.connection.sendMessage(to: self.with, text);
    }

    func messages(_ range: NSRange) -> [Message] {
        if range.location > self.messages.count {
            return [];
        } else {
            return Array(self.messages[range.location..<min(range.length, self.messages.count)]);
        }
    }

    func setChatState(_ state: ChatState) {
        self._chatStateSignal.observer.send(value: state);
    }

    func sendChatState(_ state: ChatState) {
        self.connection.sendChatState(to: self.with, state);
    }
}

// base equality on Contact (which is based on JID). TODO: this is probably an awful idea.
func ==(lhs: Conversation, rhs: Conversation) -> Bool {
    return lhs.with == rhs.with;
}
