
import Foundation;
import p2_OAuth2;

class ST {
    static let avatar = AvatarConst();
    static let conversation = ConversationConst();
    static let message = MessageConst();
    static let oauth = OAuthConst();

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

    internal class ConversationConst {
        let composeHeight = CGFloat(80);
        let composeMargin = CGFloat(6);
        let composeTextSize = CGFloat(12);

        let composeBg = NSColor.init(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.9).CGColor;

        let sendLockout = NSTimeInterval(0.1);
    }

    internal class MessageConst {
        let textAttr = [
            NSForegroundColorAttributeName: NSColor.whiteColor(),
            NSFontAttributeName: NSFont.systemFontOfSize(12)
        ];

        let bg = NSColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 0.85).CGColor;

        let margin = CGFloat(2);

        let paddingX = CGFloat(4);
        let paddingY = CGFloat(4);
        let radius = CGFloat(3);

        let calloutSize = CGFloat(4);
        let calloutVline = CGFloat(11);

        let shownFor = NSTimeInterval(5.0);
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
