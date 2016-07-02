
import Foundation
import SSKeychain

class STKeychain {
    static let sharedInstance: STKeychain = STKeychain();

    typealias Callback = (String?) -> ();

    private var _callbacks = [String : [Callback]]();
    private let _fetchingLock = NSLock();

    // get a password, but if called multiple times at once only prompts the
    // user once. threadsafe.
    func get(account: String, _ callback: Callback) {
        self._fetchingLock.lock();

        self._callbacks[account] = (self._callbacks[account] ?? []) + [callback];
        if self._callbacks[account]!.count == 1 { self._get(account); }
        self._fetchingLock.unlock();
    }

    // actually get the password. threadsafe.
    private func _get(account: String) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), {
            let password = SSKeychain.passwordForService("Sidetalk", account: account);

            self._fetchingLock.lock();
            let callbacks = self._callbacks[account]!;
            self._callbacks[account] = [Callback]();
            self._fetchingLock.unlock();

            for callback in callbacks { callback(password); }
        });
    }
}
