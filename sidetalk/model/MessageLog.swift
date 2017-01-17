
import Foundation;
import SQLite;

class MessageLog {
    private let table = Table("messages");
    private let withJID = Expression<String>("withJID");
    private let at = Expression<NSDate>("at");
    private let body = Expression<String>("body");
    private let foreign = Expression<Bool>("foreign");

    private let db: SQLite.Connection;
    private var timer: NSTimer?;
    private var pruner: Statement?;

    static func create() -> MessageLog? {
        let searchPath = NSSearchPathForDirectoriesInDomains(.ApplicationSupportDirectory, .UserDomainMask, true);
        if let path = searchPath.first {
            do {
                try NSFileManager.defaultManager().createDirectoryAtPath(path, withIntermediateDirectories: true, attributes: nil);
            } catch {
                NSLog("Unable to create library directory");
            }
            if let connection = try? SQLite.Connection("\(path)/messages.sqlite") {
                return MessageLog(connection: connection);
            }
        }
        return nil;
    }

    internal init(connection: SQLite.Connection) {
        self.db = connection;

        self.migrate();
        self.timer = NSTimer.scheduledTimerWithTimeInterval(60 * 15, target: self, selector: #selector(prune), userInfo: nil, repeats: true);
        self.pruner = try? db.prepare("delete from messages where withJID = ? and at < (select at from messages where withJID = ? order by at desc limit 1 offset 29)");
    }

    private func migrate() {
        let _ = try? db.run(table.create { schema in
            schema.column(withJID);
            schema.column(at);
            schema.column(body);
            schema.column(foreign);
        });
    }

    @objc private func prune() {
        if let prune = self.pruner {
            do {
                for row in try db.prepare("select withJID, count(at) from messages group by withJID having count(at) > 30").run() {
                    try prune.run(row[0], row[0]);
                }
            } catch {
                NSLog("Could not prune messages.");
            }
        }
    }

    func messages(forConversation conversation: Conversation, myself: Contact) -> [Message] {
        do {
            let messages = try db.prepare(table.filter(withJID == conversation.with.inner.jid().full()));
            return messages.map({ message in
                Message(from: ((message[foreign] == true) ? conversation.with : myself), body: message[body], at: message[at], conversation: conversation);
            });
        } catch {
            NSLog("Unable to load messages for user \(conversation.with.inner.jid().bare())");
            return [Message]();
        }
    }

    func log(message: Message) {
        do {
            try db.run(table.insert(
                withJID <- message.conversation.with.inner.jid().full(),
                body <- message.body,
                at <- message.at,
                foreign <- (message.conversation.with == message.from)));
        } catch {
            NSLog("Unable to save message for \(message.conversation.with.inner.jid().bare())");
        }
    }
}
