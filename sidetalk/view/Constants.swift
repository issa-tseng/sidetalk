
import Foundation;
import p2_OAuth2;

class ST {
    static let avatar = AvatarConst();
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
