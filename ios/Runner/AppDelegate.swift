import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var guardChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SmartLmsGuard") else { return }
    registerGuard(messenger: registrar.messenger())
  }

  /// Kanal "smartlms/guard" (lib/core/security/exam_guard.dart). iOS tidak menyediakan API resmi untuk
  /// memblokir screenshot: aplikasi MENDETEKSI screenshot & rekam layar lalu menutup soal.
  /// (Penguncian penuh ala ujian memerlukan entitlement AEAssessmentSession dari Apple.)
  private func registerGuard(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "smartlms/guard", binaryMessenger: messenger)
    guardChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "enable":
        result(["multiWindow": false, "captured": UIScreen.main.isCaptured])
      case "disable":
        result(nil)
      case "elapsed":
        // CLOCK_MONOTONIC di Darwin ikut berjalan saat perangkat tidur; tidak terpengaruh jam HP.
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        result(Int(ts.tv_sec) * 1000 + Int(ts.tv_nsec) / 1_000_000)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
      self?.guardChannel?.invokeMethod("screenshot", arguments: nil)
    }
    NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.guardChannel?.invokeMethod("captured", arguments: UIScreen.main.isCaptured)
    }
  }
}
