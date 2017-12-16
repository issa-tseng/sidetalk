
import Foundation

class ModeView: NSView {
    private let _hiddenModeIcon: IconView;
    private let _muteModeIcon: IconView;

    override init(frame: NSRect) {
        let hiddenIconLayer = IconLayer();
        self._hiddenModeIcon = IconView(
            layer: hiddenIconLayer,
            frame: NSRect(origin: NSPoint(x: 0, y: ST.mode.icon1Y), size: NSSize(width: ST.mode.iconSize, height: ST.mode.iconSize))
        );
        self._hiddenModeIcon.alphaValue = 0.0;
        hiddenIconLayer.image = NSImage.init(named: NSImage.Name.init(rawValue: "hidden"));

        let muteIconLayer = IconLayer();
        self._muteModeIcon = IconView(
            layer: muteIconLayer,
            frame: NSRect(origin: NSPoint(x: 0, y: ST.mode.icon1Y), size: NSSize(width: ST.mode.iconSize, height: ST.mode.iconSize))
        );
        self._muteModeIcon.alphaValue = 0.0;
        muteIconLayer.image = NSImage.init(named: NSImage.Name.init(rawValue: "mute"));

        super.init(frame: frame);
    }

    required init(coder: NSCoder) { fatalError("modecoder"); }

    override func viewWillMove(toSuperview: NSView?) {
        self.wantsLayer = true;
        super.viewWillMove(toSuperview: toSuperview);

        self.addSubview(self._hiddenModeIcon);
        self.addSubview(self._muteModeIcon);
    }

    func prepare(_ mainView: MainView) {
        // display status mode icons.
        mainView.hiddenMode.observeValues { on in
            self._hiddenModeIcon.animator().alphaValue = (on ? 1.0 : 0.0);
            self._muteModeIcon.animator().frame.origin = NSPoint(x: self._muteModeIcon.frame.origin.x, y: (on ? ST.mode.icon2Y : ST.mode.icon1Y));
        };
        mainView.mutedMode.observeValues { on in self._muteModeIcon.animator().alphaValue = (on ? 1.0 : 0.0) }
    }
}
