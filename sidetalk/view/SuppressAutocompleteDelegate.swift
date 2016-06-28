
import Foundation

class SuppressAutocompleteDelegate : NSObject, NSControlTextEditingDelegate {
    @objc func control(control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        // we have no matches for anything.
        return [];
    }
}

// please the inheritance gods.
class SuppressAutocompleteTextFieldDelegate : SuppressAutocompleteDelegate, NSTextFieldDelegate { }
