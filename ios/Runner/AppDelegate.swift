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
    registerDevicePowerChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 「動作の重さ」用: 低電力モードと本体の熱さを Flutter 側 (lib/utils/device_power.dart) に教える
  private func registerDevicePowerChannel() {
    guard let registrar = self.registrar(forPlugin: "ConningTowerDevicePower") else { return }
    let channel = FlutterMethodChannel(name: "conning_tower/device_power", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "get" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let info = ProcessInfo.processInfo
      let values: [String: Any] = ["lowPower": info.isLowPowerModeEnabled, "thermal": info.thermalState.rawValue]
      result(values)
    }
  }
}
