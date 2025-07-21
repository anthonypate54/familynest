import Flutter
import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("🚀 AppDelegate: App starting up...")
    FirebaseApp.configure()
    print("🔥 AppDelegate: Firebase configured")
    
    // Explicitly register for remote notifications
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { granted, error in
          print("📱 AppDelegate: Notification permission granted: \(granted)")
          if let error = error {
            print("❌ AppDelegate: Notification permission error: \(error)")
          }
          if granted {
            print("📱 AppDelegate: Permissions granted, calling registerForRemoteNotifications...")
            DispatchQueue.main.async {
              application.registerForRemoteNotifications()
            }
          } else {
            print("⚠️ AppDelegate: Permissions denied, push notifications will not work")
          }
        }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
      application.registerForRemoteNotifications()
    }
    
    print("📱 AppDelegate: Initial registerForRemoteNotifications() called")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - APNS Token Handling with Enhanced Logging
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("🎉 AppDelegate: SUCCESS! APNS token received from Apple")
    print("📱 AppDelegate: Token length: \(deviceToken.count) bytes")
    print("📱 AppDelegate: Token (hex): \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
    
    // Set the token in Firebase Messaging
    Messaging.messaging().apnsToken = deviceToken
    print("✅ AppDelegate: APNS token set in Firebase Messaging")
    
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ AppDelegate: CRITICAL ERROR - Failed to register for remote notifications")
    print("❌ AppDelegate: Error details: \(error.localizedDescription)")
    print("❌ AppDelegate: Error code: \((error as NSError).code)")
    print("❌ AppDelegate: Error domain: \((error as NSError).domain)")
    
    // Common error explanations
    if (error as NSError).code == 3000 {
      print("💡 AppDelegate: Error 3000 = No valid 'aps-environment' entitlement")
    } else if (error as NSError).code == 3010 {
      print("💡 AppDelegate: Error 3010 = Network error reaching Apple servers")
    }
    
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
