import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var secureTextField: UITextField?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Setup secure mode channel
    if let controller = window?.rootViewController as? FlutterViewController {
      let secureChannel = FlutterMethodChannel(
        name: "ghostty/secure",
        binaryMessenger: controller.binaryMessenger
      )
      
      secureChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "enableSecureMode" {
          self?.enableSecureMode()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func enableSecureMode() {
    DispatchQueue.main.async { [weak self] in
      guard let window = self?.window else { return }
      
      // Create a secure text field to prevent screenshots
      let field = UITextField()
      field.isSecureTextEntry = true
      field.isUserInteractionEnabled = false
      window.addSubview(field)
      window.layer.superlayer?.addSublayer(field.layer)
      field.layer.sublayers?.last?.addSublayer(window.layer)
      self?.secureTextField = field
    }
  }
  
  override func applicationWillResignActive(_ application: UIApplication) {
    // TEMPORARILY DISABLED FOR VIDEO DEMO
    // Add blur effect when app goes to background
    // if let window = self.window {
    //   let blurEffect = UIBlurEffect(style: .light)
    //   let blurView = UIVisualEffectView(effect: blurEffect)
    //   blurView.frame = window.bounds
    //   blurView.tag = 999
    //   window.addSubview(blurView)
    // }
  }
  
  override func applicationDidBecomeActive(_ application: UIApplication) {
    // Remove blur effect when app becomes active
    if let window = self.window {
      window.viewWithTag(999)?.removeFromSuperview()
    }
  }
}
