
import Foundation;
import p2_OAuth2;

class ST {
    static let avatar = AvatarConst();
    static let conversation = ConversationConst();
    static let main = MainConst();
    static let message = MessageConst();
    static let oauth = OAuthConst();

    internal class AvatarConst {
        let fallbackTextAttr: [String: AnyObject];
        let fallbackTextFrame = NSRect(x: 5.5, y: 8, width: 38, height: 30);

        let inactiveColor = NSColor.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.2).CGColor;
        let composingColor = NSColor.init(red: 0.027, green: 0.785, blue: 0.746, alpha: 0.95).CGColor;
        let attentionColor = NSColor.init(red: 0.859, green: 0.531, blue: 0.066, alpha: 1.0).CGColor;

        let selectedInactiveColor = NSColor.init(red: 1, green: 1, blue: 1, alpha: 0.85).CGColor;
        let selectedComposingColor = NSColor.init(red: 0.573, green: 0.957, blue: 0.937, alpha: 0.95).CGColor;
        let selectedAttentionColor = NSColor.init(red: 0.965, green: 0.855, blue: 0.698, alpha: 1.0).CGColor;

        let labelTextAttr = [
            NSForegroundColorAttributeName: NSColor.whiteColor(),
            NSKernAttributeName: -0.1,
            NSFontAttributeName: NSFont.systemFontOfSize(10)
        ];

        let countTextAttr = [
            NSForegroundColorAttributeName: NSColor.whiteColor(),
            NSKernAttributeName: -0.1,
            NSFontAttributeName: NSFont.boldSystemFontOfSize(9)
        ];

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

    internal class ConversationConst {
        let minHeight = CGFloat(150);

        let titleTextAttr: [String : AnyObject];
        let titleTextHeight = CGFloat(14);

        let composeHeight = CGFloat(80);
        let composeMargin = CGFloat(6);
        let composeTextSize = CGFloat(12);

        let composeBg = NSColor.init(red: 0.88, green: 0.88, blue: 0.88, alpha: 0.9).CGColor;
        let composeOutline = NSColor.init(red: 0, green: 0, blue: 0, alpha: 0.1).CGColor;

        let sendLockout = NSTimeInterval(0.1);

        private init() {
            let paragraphStyle: NSMutableParagraphStyle = NSParagraphStyle.defaultParagraphStyle().mutableCopy() as! NSMutableParagraphStyle;
            paragraphStyle.alignment = .Center;

            let shadow = NSShadow();
            shadow.shadowColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0.3);
            shadow.shadowBlurRadius = 2;
            shadow.shadowOffset = NSSize(width: 0, height: 0);

            self.titleTextAttr = [
                NSForegroundColorAttributeName: NSColor(red: 1, green: 1, blue: 1, alpha: 1),
                NSKernAttributeName: -0.1,
                NSFontAttributeName: NSFont.systemFontOfSize(10),
                NSParagraphStyleAttributeName: paragraphStyle,
                NSShadowAttributeName: shadow
            ];
        }
    }

    internal class MainConst {
        let inactiveDelay = NSTimeInterval(10.0);
    }

    internal class MessageConst {
        let textAttr = [
            NSForegroundColorAttributeName: NSColor.whiteColor(),
            NSFontAttributeName: NSFont.systemFontOfSize(12)
        ];

        let bgForeign = NSColor(red: 0, green: 0.4102, blue: 0.6484, alpha: 0.85).CGColor;
        let outlineForeign = NSColor(red: 0.7813, green: 0.8672, blue: 0.9297, alpha: 0.2).CGColor;

        let bgOwn = NSColor(red: 0.1719, green: 0.1719, blue: 0.1719, alpha: 0.95).CGColor;
        let outlineOwn = NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.15).CGColor;

        let bgTitle = NSColor(red: 0, green: 0, blue: 0, alpha: 0.9).CGColor;
        let outlineTitle = NSColor.clearColor().CGColor;

        let margin = CGFloat(2);
        let outlineWidth = CGFloat(2);

        let paddingX = CGFloat(4);
        let paddingY = CGFloat(4);
        let radius = CGFloat(6);

        let calloutSize = CGFloat(4);
        let calloutVline = CGFloat(11.5);

        let shownFor = NSTimeInterval(5.0);

        let multilineCutoff = CGFloat(15);
    }

    internal class OAuthConst {
        let settings = [
            "client_id": "844131358567-s340ookbhc1nm2rn3gcvgp5tcoo12h57.apps.googleusercontent.com",
            "authorize_uri": "https://accounts.google.com/o/oauth2/v2/auth",
            "token_uri": "https://www.googleapis.com/oauth2/v3/token",
            "scope": "email https://www.googleapis.com/auth/googletalk",
            "redirect_uris": [ "com.giantacorn.sidetalk:/oauth" ]
        ] as OAuth2JSON;
    }
}
