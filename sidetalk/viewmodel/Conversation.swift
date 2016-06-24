
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
        self.messages.append(message);
        self._latestMessageSignal.observer.sendNext(message);
    }

    func sendMessage(text: String) {
        let body = NSXMLElement(name: "body");
        body.setStringValue(text, resolvingEntities: false);

        let message = NSXMLElement(name: "message");
        message.addAttributeWithName("type", stringValue: "chat");
        message.addAttributeWithName("to", stringValue: self.with.inner.jid().full());
        message.addChild(body);

        self.connection.stream.sendElement(message);

        self.addMessage(Message(from: self.connection.myselfOnce!, body: text, at: NSDate()));
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
