import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'api_service.dart';

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static String? _fcmToken;
  static String? get fcmToken => _fcmToken;

  /// Initialize the notification service (without requesting permissions)
  static Future<void> initializeBasic() async {
    debugPrint('🔔 Initializing NotificationService (basic setup)...');

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Get and store FCM token (but don't request permissions yet)
    await _getFcmToken();

    // Set up message handlers
    _setupMessageHandlers();

    debugPrint('✅ NotificationService basic setup complete');
  }

  /// Request permissions and fully enable notifications
  static Future<bool> requestPermissionsAndEnable() async {
    debugPrint('🔔 Requesting notification permissions and enabling...');

    // Request permissions
    bool granted = await _requestPermissions();

    if (granted) {
      debugPrint('✅ Notifications fully enabled');
    } else {
      debugPrint('❌ Notification permissions denied');
    }

    return granted;
  }

  /// Initialize the notification service (DEPRECATED - use initializeBasic + requestPermissionsAndEnable)
  @deprecated
  static Future<void> initialize() async {
    await initializeBasic();
    await requestPermissionsAndEnable();
  }

  /// Check current notification permission status (for debugging)
  static Future<void> checkPermissionStatus() async {
    debugPrint('🔍 Checking current notification permission status...');

    try {
      NotificationSettings settings =
          await _firebaseMessaging.getNotificationSettings();
      debugPrint('🔍 Authorization Status: ${settings.authorizationStatus}');
      debugPrint('🔍 Alert: ${settings.alert}');
      debugPrint('🔍 Badge: ${settings.badge}');
      debugPrint('🔍 Sound: ${settings.sound}');
      debugPrint('🔍 Announcement: ${settings.announcement}');
      debugPrint('🔍 CarPlay: ${settings.carPlay}');
      debugPrint('🔍 Critical Alert: ${settings.criticalAlert}');

      // Friendly explanation
      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          debugPrint('✅ Status: Fully authorized');
          break;
        case AuthorizationStatus.provisional:
          debugPrint('⚠️ Status: Provisional (quiet notifications)');
          break;
        case AuthorizationStatus.denied:
          debugPrint('❌ Status: Denied - must enable in device settings');
          break;
        case AuthorizationStatus.notDetermined:
          debugPrint('❓ Status: Not determined - permission dialog will show');
          break;
      }
    } catch (e) {
      debugPrint('❌ Error checking permission status: $e');
    }
  }

  /// Request notification permissions from the user
  static Future<bool> _requestPermissions() async {
    debugPrint('📱 Requesting notification permissions...');
    debugPrint('📱 Platform: ${Platform.operatingSystem}');

    try {
      // Check current status before requesting
      NotificationSettings currentSettings =
          await _firebaseMessaging.getNotificationSettings();
      debugPrint(
        '📱 BEFORE REQUEST - Current status: ${currentSettings.authorizationStatus}',
      );
      debugPrint('📱 BEFORE REQUEST - Alert: ${currentSettings.alert}');
      debugPrint('📱 BEFORE REQUEST - Badge: ${currentSettings.badge}');
      debugPrint('📱 BEFORE REQUEST - Sound: ${currentSettings.sound}');

      // Special check for iOS - if already determined, explain why no dialog shows
      if (Platform.isIOS) {
        if (currentSettings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint(
            '⚠️ iOS: Permissions previously denied - no dialog will show',
          );
          debugPrint(
            '⚠️ iOS: User must enable manually in Settings > Notifications > FamilyNest',
          );
          return false;
        }
        if (currentSettings.authorizationStatus ==
            AuthorizationStatus.authorized) {
          debugPrint('✅ iOS: Permissions already granted - no dialog needed');
          return true;
        }
      }

      debugPrint('📱 About to call Firebase requestPermission()...');

      // Add a small delay to ensure the dialog context is ready
      await Future.delayed(const Duration(milliseconds: 100));

      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );
      debugPrint('📱 Firebase requestPermission() completed');
      debugPrint(
        '📱 AFTER REQUEST - New status: ${settings.authorizationStatus}',
      );
      debugPrint('📱 AFTER REQUEST - Alert: ${settings.alert}');
      debugPrint('📱 AFTER REQUEST - Badge: ${settings.badge}');
      debugPrint('📱 AFTER REQUEST - Sound: ${settings.sound}');

      // iOS Simulator warning
      if (Platform.isIOS) {
        debugPrint(
          '📱 iOS NOTE: If running on Simulator, permission dialogs may not appear',
        );
        debugPrint(
          '📱 iOS NOTE: Try on a physical device for full permission dialog experience',
        );
      }

      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          debugPrint('✅ Notification permissions granted');
          return true;
        case AuthorizationStatus.provisional:
          debugPrint('⚠️ Provisional notification permissions granted');
          return true;
        case AuthorizationStatus.denied:
          debugPrint('❌ Notification permissions denied');
          return false;
        case AuthorizationStatus.notDetermined:
          debugPrint('❓ Notification permissions not determined');
          return false;
      }
    } catch (e) {
      debugPrint('❌ Error requesting permissions: $e');
      return false;
    }
  }

  /// Initialize local notifications for foreground display
  static Future<void> _initializeLocalNotifications() async {
    debugPrint('🏠 Initializing local notifications...');

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    debugPrint('✅ Local notifications initialized');
  }

  /// Get and store the FCM token
  static Future<void> _getFcmToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      debugPrint('🔑 FCM Token obtained: $_fcmToken');

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((token) {
        debugPrint('🔄 FCM Token refreshed: $token');
        _fcmToken = token;
        // TODO: Send updated token to backend
      });
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
    }
  }

  /// Set up message handlers for different app states
  static void _setupMessageHandlers() {
    debugPrint('📬 Setting up message handlers...');

    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle messages when app is opened from background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Handle messages when app is opened from terminated state
    _firebaseMessaging.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint('🚀 App opened from terminated state by notification');
        _handleMessageOpenedApp(message);
      }
    });

    debugPrint('✅ Message handlers set up');
  }

  /// Handle messages when app is in foreground
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('🔔 Foreground message received: ${message.messageId}');
    debugPrint('📱 Title: ${message.notification?.title}');
    debugPrint('📝 Body: ${message.notification?.body}');
    debugPrint('📊 Data: ${message.data}');

    // Show local notification when app is in foreground
    await _showLocalNotification(message);
  }

  /// Handle messages when app is opened from background/terminated
  static void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('🚪 App opened by notification: ${message.messageId}');
    debugPrint('📊 Data: ${message.data}');

    // TODO: Navigate to specific screen based on message data
    // For example, if it's a family message, navigate to that family's thread
    _handleNotificationNavigation(message.data);
  }

  /// Show local notification for foreground messages
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'familynest_channel',
            'FamilyNest Notifications',
            channelDescription: 'Notifications for family messages and updates',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        message.hashCode, // Use message hash as unique ID
        message.notification?.title ?? 'FamilyNest',
        message.notification?.body ?? 'You have a new message',
        notificationDetails,
        payload: message.data.toString(),
      );

      debugPrint('✅ Local notification shown');
    } catch (e) {
      debugPrint('❌ Error showing local notification: $e');
    }
  }

  /// Handle notification tap events
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('👆 Notification tapped: ${response.payload}');

    // TODO: Parse payload and navigate to appropriate screen
    if (response.payload != null) {
      // Parse the data and navigate accordingly
      debugPrint('📊 Payload: ${response.payload}');
    }
  }

  /// Handle navigation based on notification data
  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    debugPrint('🧭 Handling notification navigation with data: $data');

    // TODO: Implement navigation logic based on notification type
    // Examples:
    // - Family message -> Navigate to family thread
    // - DM message -> Navigate to DM conversation
    // - Member joined -> Navigate to family management

    String? notificationType = data['type'];
    String? familyId = data['familyId'];
    String? messageId = data['messageId'];

    debugPrint(
      '🏷️ Type: $notificationType, Family: $familyId, Message: $messageId',
    );
  }

  /// Send FCM token to backend (to be called after user login)
  static Future<void> sendTokenToBackend(
    String userId,
    ApiService apiService,
  ) async {
    if (_fcmToken == null) {
      debugPrint('⚠️ No FCM token available to send to backend');
      return;
    }

    debugPrint('📤 Sending FCM token to backend for user: $userId');

    try {
      final success = await apiService.registerFcmToken(userId, _fcmToken!);
      if (success) {
        debugPrint('✅ FCM token sent to backend successfully');
      } else {
        debugPrint('⚠️ Failed to send FCM token to backend');
      }
    } catch (e) {
      debugPrint('❌ Error sending FCM token to backend: $e');
      rethrow; // Let caller handle the error
    }
  }

  /// Check current notification permission status
  static Future<bool> hasNotificationPermission() async {
    debugPrint(
      '🔍 NOTIFICATION: Checking current notification permission status...',
    );

    // Add platform-specific debugging
    debugPrint('🔍 NOTIFICATION: Platform: ${Platform.operatingSystem}');
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        debugPrint(
          '🔍 NOTIFICATION: Android API Level: ${androidInfo.version.sdkInt}',
        );
        debugPrint(
          '🔍 NOTIFICATION: Android Version: ${androidInfo.version.release}',
        );
      } catch (e) {
        debugPrint('🔍 NOTIFICATION: Could not get Android info: $e');
      }
    }

    NotificationSettings settings =
        await _firebaseMessaging.getNotificationSettings();

    debugPrint('🔍 NOTIFICATION: Raw settings object: $settings');
    debugPrint(
      '🔍 NOTIFICATION: Authorization status: ${settings.authorizationStatus}',
    );
    debugPrint('🔍 NOTIFICATION: Alert setting: ${settings.alert}');
    debugPrint('🔍 NOTIFICATION: Badge setting: ${settings.badge}');
    debugPrint('🔍 NOTIFICATION: Sound setting: ${settings.sound}');
    debugPrint(
      '🔍 NOTIFICATION: Announcement setting: ${settings.announcement}',
    );
    debugPrint(
      '🔍 NOTIFICATION: Critical alert setting: ${settings.criticalAlert}',
    );

    final bool hasPermission =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    debugPrint('🔍 NOTIFICATION: hasPermission result: $hasPermission');

    return hasPermission;
  }

  /// Show a dialog to explain notification permissions
  static void showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Enable Notifications'),
            content: const Text(
              'FamilyNest would like to send you notifications for new family messages and updates. '
              'You can change this setting anytime in your device settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not Now'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _requestPermissions();
                },
                child: const Text('Enable'),
              ),
            ],
          ),
    );
  }
}
