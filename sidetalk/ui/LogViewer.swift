import Foundation;

class LogViewerController: NSViewController {
    @IBOutlet var _textView: NSTextView!

    func setText(text: NSAttributedString) {
        if let field = self._textView {
            field.textStorage!.setAttributedString(text);
            field.editable = false;
        }
    }
}
