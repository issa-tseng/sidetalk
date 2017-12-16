import Foundation
import CocoaLumberjack

class STMemoryLogger: NSObject, DDLogger {
    static let sharedInstance = STMemoryLogger();

    @objc var logFormatter: DDLogFormatter;

    private var _log = [String]();
    private let _maxSize: Int;

    init(maxSize: Int = 30) {
        self._maxSize = maxSize;
        self.logFormatter = DDLogFileFormatterDefault();
    }

    @objc func log(message logMessage: DDLogMessage) {
        self._log.append("[\(logMessage.timestamp)] \(logMessage.message)");
        if self._log.count > self._maxSize { self._log.removeFirst(); }
    }

    func all() -> String {
        return self._log.joined(separator: "\n");
    }
}
