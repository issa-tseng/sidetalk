
import Foundation

class ST {
    static let avatar = AvatarConst();

    internal class AvatarConst {
        let fallbackTextAttr: [String: AnyObject];
        let fallbackTextFrame = NSRect(x: 5.5, y: 8, width: 38, height: 30);

        private init() {
            // set up fallback text attrs.
            let paragraphStyle: NSMutableParagraphStyle = NSParagraphStyle.defaultParagraphStyle().mutableCopy() as! NSMutableParagraphStyle;
            paragraphStyle.alignment = .Center;

            self.fallbackTextAttr = [
                NSForegroundColorAttributeName: NSColor.whiteColor(),
                NSKernAttributeName: -0.2,
                NSFontAttributeName: NSFont.systemFontOfSize(22),
                NSParagraphStyleAttributeName: paragraphStyle
            ];

        }
    }
}
