
import Foundation;
import p2_OAuth2;

class ST {
    static let avatar = AvatarConst();
    static let conversation = ConversationConst();
    static let main = MainConst();
    static let message = MessageConst();
    static let mode = ModeConst();
    static let oauth = OAuthConst();

    internal class AvatarConst {
        let fallbackTextAttr: [NSAttributedStringKey: Any];
        let fallbackTextFrame = NSRect(x: 5.5, y: 8, width: 38, height: 30);

        let inactiveColor = NSColor.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.2).cgColor;
        let composingColor = NSColor.init(red: 0.027, green: 0.785, blue: 0.746, alpha: 0.95).cgColor;
        let attentionColor = NSColor.init(red: 0.859, green: 0.531, blue: 0.066, alpha: 1.0).cgColor;

        let selectedInactiveColor = NSColor.init(red: 1, green: 1, blue: 1, alpha: 0.85).cgColor;
        let selectedComposingColor = NSColor.init(red: 0.573, green: 0.957, blue: 0.937, alpha: 0.95).cgColor;
        let selectedAttentionColor = NSColor.init(red: 0.965, green: 0.855, blue: 0.698, alpha: 1.0).cgColor;

        let labelTextAttr: [NSAttributedStringKey: Any] = [
            NSAttributedStringKey.foregroundColor: NSColor.white,
            NSAttributedStringKey.kern: -0.1,
            NSAttributedStringKey.font: NSFont.systemFont(ofSize: 10)
        ];

        let countTextAttr: [NSAttributedStringKey: Any] = [
            NSAttributedStringKey.foregroundColor: NSColor.white,
            NSAttributedStringKey.kern: -0.1,
            NSAttributedStringKey.font: NSFont.boldSystemFont(ofSize: 9)
        ];

        internal init() {
            // set up fallback text attrs.
            let paragraphStyle: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle;
            paragraphStyle.alignment = .center;

            self.fallbackTextAttr = [
                NSAttributedStringKey.foregroundColor: NSColor.white,
                NSAttributedStringKey.kern: -0.2,
                NSAttributedStringKey.font: NSFont.systemFont(ofSize: 22),
                NSAttributedStringKey.paragraphStyle: paragraphStyle
            ];

        }
    }

    internal class ConversationConst {
        let minHeight = CGFloat(150);

        let titleTextAttr: [NSAttributedStringKey: Any];
        let titleTextHeight = CGFloat(14);

        let composeHeight = CGFloat(80);
        let composeMargin = CGFloat(6);
        let composeTextSize = CGFloat(12);

        let composeBg = NSColor.init(red: 0.97, green: 0.97, blue: 0.97, alpha: 0.9).cgColor;
        let composeOutline = NSColor.init(red: 0, green: 0, blue: 0, alpha: 0.0).cgColor;

        let sendLockout = TimeInterval(0.1);

        internal init() {
            let paragraphStyle: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle;
            paragraphStyle.alignment = .center;

            let shadow = NSShadow();
            shadow.shadowColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0.3);
            shadow.shadowBlurRadius = 2;
            shadow.shadowOffset = NSSize(width: 0, height: 0);

            self.titleTextAttr = [
                NSAttributedStringKey.foregroundColor: NSColor(red: 1, green: 1, blue: 1, alpha: 1),
                NSAttributedStringKey.kern: -0.1,
                NSAttributedStringKey.font: NSFont.systemFont(ofSize: 10),
                NSAttributedStringKey.paragraphStyle: paragraphStyle,
                NSAttributedStringKey.shadow: shadow
            ];
        }
    }

    internal class MainConst {
        let inactiveDelay = TimeInterval(10.0);

        let boldFont = NSFont.boldSystemFont(ofSize: 13);
    }

    internal class MessageConst {
        let textAttr = [
            NSAttributedStringKey.foregroundColor: NSColor.white,
            NSAttributedStringKey.font: NSFont.systemFont(ofSize: 12)
        ];

        let bgForeign = NSColor(red: 0, green: 0.4102, blue: 0.6484, alpha: 0.85).cgColor;
        let bgOwn = NSColor(red: 0.14, green: 0.14, blue: 0.14, alpha: 0.95).cgColor;
        let bgTitle = NSColor.clear.cgColor;
        let margin = CGFloat(3);

        let paddingX = CGFloat(7);
        let paddingY = CGFloat(5);
        let radius = CGFloat(7);

        let calloutSize = CGFloat(4);
        let calloutVline = CGFloat(11.5);

        let shownFor = TimeInterval(5.0);

        let multilineCutoff = CGFloat(15);
    }

    internal class ModeConst {
        let marginBottom = CGFloat(10);
        let marginRight = CGFloat(4);
        let iconSize = CGFloat(20);
        let icon1Y = CGFloat(20);
        let icon2Y = CGFloat(0);
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
