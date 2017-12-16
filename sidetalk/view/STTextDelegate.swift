
import Foundation;
import ReactiveSwift;
import enum Result.NoError;

// does two things: provides a signal representing the current value of the text field, and suppresses autocomplete.
private var _stringValueContext = 0;
class STTextDelegate : NSObject, NSControlTextEditingDelegate, NSTextFieldDelegate {
    private let _field: NSTextField;

    init(field: NSTextField) {
        self._field = field;
        super.init();

        field.addObserver(self, forKeyPath: "stringValue", options: NSKeyValueObservingOptions(), context: &_stringValueContext);
        field.delegate = self;
    }
    deinit {
        self._field.removeObserver(self, forKeyPath: "stringValue", context: &_stringValueContext);
    }

    // detect programmtic changes to stringValue property.
    private let _text = ManagedSignal<String>();
    var text: Signal<String, NoError> { get { return self._text.signal; } }
    @objc override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context != &_stringValueContext {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context);
            return;
        }

        if ((object as? NSTextField) == self._field) && (keyPath ?? "") == "stringValue" {
            self._text.observer.send(value: self._field.stringValue);
        }
    }

    // detect user-initiated text changes.
    @objc override func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            self._text.observer.send(value: field.stringValue ?? "");
        }
    }

    // suppress autocomplete.
    @objc func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        // we have no matches for anything.
        return [];
    }
}
