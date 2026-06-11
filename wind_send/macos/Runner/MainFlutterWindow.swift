import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "wind_send/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setOpacity",
            let opacity = call.arguments as? Double else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.alphaValue = min(1.0, max(0.35, opacity))
      result(nil)
    }

    super.awakeFromNib()
  }
}
