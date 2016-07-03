
import Foundation;
import ReactiveCocoa;
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
    @objc override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context != &_stringValueContext {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context);
            return;
        }

        if ((object as? NSTextField) == self._field) && (keyPath ?? "") == "stringValue" {
            self._text.observer.sendNext(self._field.stringValue);
        }
    }

    // detect user-initiated text changes.
    @objc override func controlTextDidChange(obj: NSNotification) {
        if let field = obj.object as? NSTextField {
            self._text.observer.sendNext(field.stringValue ?? "");
        }
    }

    // suppress autocomplete.
    @objc func control(control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        // we have no matches for anything.
        return [];
    }
}
