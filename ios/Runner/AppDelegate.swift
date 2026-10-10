import UIKit
import Flutter
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // This is required to make any communication available in the action isolate.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
        GeneratedPluginRegistrant.register(with: registry)
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)
    registerOrientationChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Tells Flutter which way the screen is rotated, so the landscape menu can be placed on the camera side.
  /// (iOS reports the same safe area on both sides in landscape, so Flutter alone cannot tell.)
  private func registerOrientationChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "conning_tower/orientation", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak controller] (call, result) in
      guard call.method == "interfaceOrientation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      var orientation: UIInterfaceOrientation = .unknown
      if #available(iOS 13.0, *) {
        orientation = controller?.view.window?.windowScene?.interfaceOrientation ?? .unknown
      } else {
        orientation = UIApplication.shared.statusBarOrientation
      }
      switch orientation {
      case .landscapeLeft: result("landscapeLeft")   // home indicator on the left, camera on the right
      case .landscapeRight: result("landscapeRight") // home indicator on the right, camera on the left
      case .portrait: result("portrait")
      case .portraitUpsideDown: result("portraitUpsideDown")
      default: result("unknown")
      }
    }
  }
}
