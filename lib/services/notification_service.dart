import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:math';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // For iOS, we might need to request permissions first to get APNS token
    if (Platform.isIOS) {
      debugPrint(
        '📱 iOS detected - checking if we should request permissions first...',
      );

      // Check current permission status
      NotificationSettings settings =
          await _firebaseMessaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        debugPrint(
          '📱 iOS permissions not determined - requesting now for APNS token...',
        );
        await _requestPermissions();
      }
    }

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
      debugPrint('🔑 Getting FCM token for device...');

      // For iOS, use the improved APNS handling approach
      if (Platform.isIOS) {
        debugPrint('📱 iOS detected - using improved APNS handling...');

        // Check if running on simulator
        try {
          final deviceInfo = DeviceInfoPlugin();
          final iosInfo = await deviceInfo.iosInfo;
          debugPrint('📱 Device name: ${iosInfo.name}');
          debugPrint('📱 Device model: ${iosInfo.model}');
          debugPrint(
            '📱 Is simulator: ${iosInfo.isPhysicalDevice ? "NO (Real Device)" : "YES (Simulator)"}',
          );

          if (!iosInfo.isPhysicalDevice) {
            debugPrint(
              '⚠️ SIMULATOR DETECTED: APNS tokens do NOT work on iOS Simulator!',
            );
            debugPrint(
              '⚠️ You must use a real physical iPhone for push notifications to work.',
            );
            return;
          }
        } catch (e) {
          debugPrint('❌ Error checking device info: $e');
        }

        // Step 1: Request permissions
        debugPrint('📱 Requesting notification permissions...');
        NotificationSettings settings = await _firebaseMessaging
            .requestPermission(
              alert: true,
              badge: true,
              sound: true,
              provisional: true,
            );

        debugPrint('📱 Permission status: ${settings.authorizationStatus}');

        if (settings.authorizationStatus != AuthorizationStatus.authorized) {
          debugPrint('❌ Permissions denied. User needs to enable in Settings.');
          if (settings.authorizationStatus == AuthorizationStatus.denied) {
            debugPrint(
              '⚠️ User denied permissions - notifications will not work',
            );
          } else if (settings.authorizationStatus ==
              AuthorizationStatus.notDetermined) {
            debugPrint('⚠️ Permissions not determined - retry needed');
          }

          try {
            final apiService = ApiService();
            await apiService.backendDebugPrint(
              'iOS_PERMISSIONS_NOT_AUTHORIZED: ${settings.authorizationStatus}',
            );
          } catch (e) {
            debugPrint('Debug logging failed: $e');
          }
          return;
        }

        // Step 2: Configure foreground notification presentation (triggers APNS registration)
        debugPrint('📱 Configuring foreground notification presentation...');
        await _firebaseMessaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Step 3: Retry fetching APNS token with delay (up to 10 seconds)
        debugPrint('📱 Attempting to get APNS token with retries...');
        String? apnsToken;
        for (int i = 0; i < 5; i++) {
          apnsToken = await _firebaseMessaging.getAPNSToken();
          if (apnsToken != null) {
            debugPrint(
              '✅ APNS token obtained on attempt ${i + 1}: ${apnsToken.substring(0, 10)}...',
            );
            try {
              final apiService = ApiService();
              await apiService.backendDebugPrint(
                'APNS_TOKEN_SUCCESS: Attempt ${i + 1}, Length ${apnsToken.length}',
              );
            } catch (e) {
              debugPrint('Debug logging failed: $e');
            }
            break;
          }
          debugPrint(
            '⏳ APNS token null on attempt ${i + 1}. Retrying in 2 seconds...',
          );
          if (i < 4) {
            // Don't delay after the last attempt
            await Future.delayed(const Duration(seconds: 2));
          }
        }

        if (apnsToken == null) {
          debugPrint('❌ Failed to get APNS token after 5 retries.');
          debugPrint('💡 This could mean:');
          debugPrint('   1. Network connectivity issues');
          debugPrint('   2. Apple APNS servers temporarily unavailable');
          debugPrint('   3. Firebase APNS key configuration problem');
          debugPrint('   4. iOS device registration issues');

          try {
            final apiService = ApiService();
            await apiService.backendDebugPrint(
              'APNS_TOKEN_FAILED_AFTER_5_RETRIES',
            );
          } catch (e) {
            debugPrint('Debug logging failed: $e');
          }

          // Still try to get FCM token - sometimes it works despite APNS issues
          debugPrint(
            '📱 Attempting FCM token generation despite APNS failure...',
          );
        } else {
          debugPrint(
            '✅ APNS token successfully obtained, proceeding with FCM token...',
          );
        }
      }

      // Step 4: Now get FCM token (should work for both platforms)
      try {
        debugPrint('🔑 Attempting FCM token generation...');
        _fcmToken = await _firebaseMessaging.getToken();

        if (_fcmToken != null) {
          debugPrint(
            '🔑 FCM Token obtained successfully: ${_fcmToken?.substring(0, 20)}...',
          );
          debugPrint('🔑 FCM Token length: ${_fcmToken?.length ?? 0}');

          // DEBUG: Log success to backend
          try {
            final apiService = ApiService();
            await apiService.backendDebugPrint(
              'FCM_TOKEN_SUCCESS: Length ${_fcmToken?.length ?? 0}',
            );
            if (_fcmToken != null) {
              await apiService.backendDebugPrint(
                'FCM_TOKEN_PREFIX: ${_fcmToken!.substring(0, min(30, _fcmToken!.length))}',
              );
            }
          } catch (e) {
            debugPrint('Debug logging failed: $e');
          }
        } else {
          debugPrint('❌ FCM token is null - generation failed');
          try {
            final apiService = ApiService();
            await apiService.backendDebugPrint('FCM_TOKEN_NULL');
          } catch (e) {
            debugPrint('Debug logging failed: $e');
          }
        }
      } catch (e) {
        debugPrint('❌ Error getting FCM token: $e');
        debugPrint(
          '⚠️ FCM token generation failed - notifications will not work',
        );

        // DEBUG: Send the error to backend logs for real device debugging
        try {
          final apiService = ApiService();
          await apiService.backendDebugPrint('FCM_TOKEN_GENERATION_FAILED: $e');
          await apiService.backendDebugPrint(
            'DEVICE_PLATFORM: ${Platform.operatingSystem}',
          );
          await apiService.backendDebugPrint(
            'ERROR_TYPE: FCM_GENERATION_ERROR',
          );
        } catch (debugError) {
          debugPrint('❌ Debug logging failed: $debugError');
        }
        return;
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((token) async {
        debugPrint('🔄 FCM Token refreshed: ${token.substring(0, 20)}...');
        _fcmToken = token;

        // Send updated token to backend
        try {
          final currentUserId = await _getCurrentUserIdFromAPI();
          if (currentUserId != null) {
            final apiService = ApiService();
            final success = await apiService.registerFcmToken(
              currentUserId,
              token,
            );
            if (success) {
              debugPrint('✅ Updated FCM token sent to backend successfully');
            } else {
              debugPrint('⚠️ Failed to send updated FCM token to backend');
            }
          } else {
            debugPrint('⚠️ No current user ID available for token update');
          }
        } catch (e) {
          debugPrint('❌ Error sending updated FCM token to backend: $e');
        }
      });
    } catch (e) {
      debugPrint('❌ Error in _getFcmToken: $e');
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

    // Check if current user is the sender - don't show notification to sender
    final senderId = message.data['senderId'];
    final currentUserId = await _getCurrentUserIdFromAPI();

    debugPrint(
      '🔍 DEBUG: senderId from message: "$senderId" (${senderId.runtimeType})',
    );
    debugPrint(
      '🔍 DEBUG: currentUserId from API: "$currentUserId" (${currentUserId.runtimeType})',
    );
    debugPrint(
      '🔍 DEBUG: String comparison: "${senderId.toString()}" == "${currentUserId.toString()}" = ${senderId.toString() == currentUserId.toString()}',
    );

    if (senderId != null &&
        currentUserId != null &&
        senderId.toString() == currentUserId.toString()) {
      debugPrint('🚫 Skipping notification - current user is the sender');
      return;
    }

    debugPrint('✅ Showing notification - different user');
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
    debugPrint('🚀 SEND_TOKEN_TO_BACKEND: Starting for user: $userId');
    debugPrint('🚀 SEND_TOKEN_TO_BACKEND: Current FCM token: $_fcmToken');
    debugPrint('🚀 SEND_TOKEN_TO_BACKEND: Token is null: ${_fcmToken == null}');
    debugPrint(
      '🚀 SEND_TOKEN_TO_BACKEND: Token length: ${_fcmToken?.length ?? 0}',
    );
    await apiService.backendDebugPrint(
      '### FROM FRONT Made it to sendTokenBackend',
    );

    if (_fcmToken == null) {
      debugPrint(
        '⚠️ SEND_TOKEN_TO_BACKEND: No FCM token available to send to backend',
      );
      debugPrint('🔄 SEND_TOKEN_TO_BACKEND: Attempting to get fresh token...');

      // Try to get token again
      try {
        _fcmToken = await _firebaseMessaging.getToken();
        debugPrint(
          '🔑 SEND_TOKEN_TO_BACKEND: Fresh token obtained: $_fcmToken',
        );
      } catch (e) {
        debugPrint('❌ SEND_TOKEN_TO_BACKEND: Failed to get fresh token: $e');
        await apiService.backendDebugPrint('###EXCEPTION $e');

        return;
      }

      if (_fcmToken == null) {
        debugPrint(
          '❌ SEND_TOKEN_TO_BACKEND: Still no token after refresh attempt',
        );
        await apiService.backendDebugPrint(
          '###SEND_TOKEN_TO_BACKEND:_fcmToken is null returning',
        );

        return;
      }
    }

    debugPrint(
      '📤 SEND_TOKEN_TO_BACKEND: Sending FCM token to backend for user: $userId',
    );
    debugPrint('📤 SEND_TOKEN_TO_BACKEND: Token length: ${_fcmToken!.length}');

    try {
      // First print the token to backend logs
      debugPrint('🔍 SEND_TOKEN_TO_BACKEND: Sending token to backend logs...');
      await apiService.backendDebugPrint(
        'FCM_TOKEN_FOR_USER_$userId: $_fcmToken',
      );
      await apiService.backendDebugPrint(
        'FCM_TOKEN_LENGTH: ${_fcmToken!.length}',
      );
      if (_fcmToken!.startsWith('ios_simulator_mock_token_')) {
        await apiService.backendDebugPrint('TOKEN_TYPE: MOCK_SIMULATOR_TOKEN');
      } else if (_fcmToken!.contains(':') && _fcmToken!.length > 100) {
        await apiService.backendDebugPrint('TOKEN_TYPE: REAL_FCM_TOKEN');
      } else {
        await apiService.backendDebugPrint('TOKEN_TYPE: UNKNOWN_FORMAT');
      }

      // Then call the real registration endpoint
      final success = await apiService.registerFcmToken(userId, _fcmToken!);
      if (success) {
        debugPrint(
          '✅ SEND_TOKEN_TO_BACKEND: FCM token sent to backend successfully',
        );
      } else {
        debugPrint(
          '⚠️ SEND_TOKEN_TO_BACKEND: Failed to send FCM token to backend',
        );
      }
    } catch (e) {
      debugPrint(
        '❌ SEND_TOKEN_TO_BACKEND: Error sending FCM token to backend: $e',
      );
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

  /// Get current user ID to check against sender
  static Future<String?> _getCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      // Debug: Print all auth-related SharedPreferences
      final allKeys = prefs.getKeys();
      debugPrint('🔍 DEBUG: All SharedPreferences keys: $allKeys');
      debugPrint('🔍 DEBUG: user_id = "${prefs.getString('user_id')}"');
      debugPrint(
        '🔍 DEBUG: auth_token exists = ${prefs.containsKey('auth_token')}',
      );
      debugPrint('🔍 DEBUG: is_logged_in = ${prefs.getBool('is_logged_in')}');

      return userId;
    } catch (e) {
      debugPrint('❌ Error getting current user ID: $e');
      return null;
    }
  }

  /// Get current user ID from API (to be called when app is in foreground)
  static Future<String?> _getCurrentUserIdFromAPI() async {
    try {
      final apiService = ApiService();
      final userId = await apiService.getCurrentUserId();
      debugPrint('🔑 FCM Token: $_fcmToken, Current User ID from API: $userId');
      return userId;
    } catch (e) {
      debugPrint('❌ Error getting current user ID from API: $e');
      return null;
    }
  }

  /// Force refresh FCM token and send to backend (useful for testing)
  static Future<bool> forceRefreshToken() async {
    debugPrint('🔄 Force refreshing FCM token...');

    try {
      // First, let's check what APNS token returns directly
      if (Platform.isIOS) {
        debugPrint('🔍 DEBUG: Checking APNS token directly...');

        // Check if running on simulator
        try {
          final deviceInfo = DeviceInfoPlugin();
          final iosInfo = await deviceInfo.iosInfo;
          debugPrint('📱 Device name: ${iosInfo.name}');
          debugPrint('📱 Device model: ${iosInfo.model}');
          debugPrint(
            '📱 Is simulator: ${iosInfo.isPhysicalDevice ? "NO (Real Device)" : "YES (Simulator)"}',
          );

          if (!iosInfo.isPhysicalDevice) {
            debugPrint(
              '⚠️ SIMULATOR DETECTED: APNS tokens do NOT work on iOS Simulator!',
            );
            debugPrint(
              '⚠️ You must use a real physical iPhone for push notifications to work.',
            );
          }
        } catch (e) {
          debugPrint('❌ Error checking device info: $e');
        }

        try {
          String? apnsToken = await _firebaseMessaging.getAPNSToken();
          if (apnsToken == null) {
            debugPrint('❌ DEBUG: getAPNSToken() returned NULL');
          } else {
            debugPrint(
              '✅ DEBUG: getAPNSToken() returned: ${apnsToken.substring(0, 10)}...',
            );
          }
        } catch (e) {
          debugPrint('❌ DEBUG: getAPNSToken() threw error: $e');
        }
      }

      // Delete the current token to force Firebase to generate a new one
      await _firebaseMessaging.deleteToken();
      debugPrint('🗑️ Deleted old FCM token');

      // Use our improved FCM token generation logic
      await _getFcmToken();

      // Check if we got a new token
      if (_fcmToken != null) {
        debugPrint(
          '🔑 New FCM Token obtained: ${_fcmToken!.substring(0, 20)}...',
        );

        // Send to backend
        final currentUserId = await _getCurrentUserIdFromAPI();
        if (currentUserId != null) {
          final apiService = ApiService();
          final success = await apiService.registerFcmToken(
            currentUserId,
            _fcmToken!,
          );
          if (success) {
            debugPrint(
              '✅ Force refreshed FCM token sent to backend successfully',
            );
            return true;
          } else {
            debugPrint(
              '⚠️ Failed to send force refreshed FCM token to backend',
            );
            return false;
          }
        } else {
          debugPrint('⚠️ No current user ID available for force refresh');
          return false;
        }
      } else {
        debugPrint('❌ Failed to obtain new FCM token');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error force refreshing FCM token: $e');
      return false;
    }
  }
}
