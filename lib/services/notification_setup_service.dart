import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'notification_service.dart';
import 'api_service.dart';

class NotificationSetupService {
  /// Check if user needs to see notification dialog and show it if needed
  /// Returns true if notification setup was completed (or skipped), false if cancelled
  static Future<bool> handleNotificationSetup(
    BuildContext context,
    int userId,
    String userRole,
  ) async {
    debugPrint('🔔 NOTIFICATION_SETUP: Starting for user $userId');

    // Check if user has already seen the notification dialog
    bool hasSeenDialog = await hasSeenNotificationDialog(userId);
    if (hasSeenDialog) {
      debugPrint(
        '🔔 NOTIFICATION_SETUP: User $userId already saw dialog, skipping',
      );
      return true;
    }

    // Check if permissions are already granted
    bool hasPermission = await NotificationService.hasNotificationPermission();
    if (hasPermission) {
      debugPrint(
        '🔔 NOTIFICATION_SETUP: Permissions already granted, calling enable-all API directly',
      );

      // Still need to call enable-all API to set database flags
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        bool success = await apiService.enableAllNotificationPreferences(
          userId,
        );
        debugPrint('🔔 NOTIFICATION_SETUP: Enable-all API result: $success');

        if (success) {
          debugPrint(
            '✅ NOTIFICATION_SETUP: All notification preferences enabled (pre-granted permissions)',
          );
        } else {
          debugPrint(
            '❌ NOTIFICATION_SETUP: Failed to enable notification preferences',
          );
        }
      } catch (e) {
        debugPrint('❌ NOTIFICATION_SETUP: Error enabling preferences: $e');
      }

      await markNotificationDialogSeen(userId);
      return true;
    }

    // Show notification permission dialog
    debugPrint('🔔 NOTIFICATION_SETUP: Showing notification dialog');
    return await _showNotificationDialog(context, userId, userRole);
  }

  /// Show the notification permission dialog
  static Future<bool> _showNotificationDialog(
    BuildContext context,
    int userId,
    String userRole,
  ) async {
    bool completed = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // User must make a choice
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.notifications_outlined, color: Colors.blue),
                SizedBox(width: 8),
                Text('Enable Notifications'),
              ],
            ),
            content: const Text(
              'FamilyNest needs permission to send you notifications for family messages, photos, and updates.\n\n'
              'Important: If you choose "Not Now", you\'ll need to manually enable notifications in your device settings later.\n\n'
              'Once enabled, you can control specific notification types (DMs, family messages, etc.) in our app settings.\n\n'
              'Note: Most devices already allow notifications by default.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  completed = true; // User declined but completed the dialog
                },
                child: const Text('Not Now'),
              ),
              ElevatedButton(
                onPressed: () async {
                  debugPrint(
                    '🔔 NOTIFICATION_SETUP: User chose to enable notifications',
                  );
                  debugPrint(
                    '🔔 NOTIFICATION_SETUP: About to request Firebase permissions...',
                  );

                  // Request Firebase permissions first
                  bool granted =
                      await NotificationService.requestPermissionsAndEnable();
                  debugPrint(
                    '🔔 NOTIFICATION_SETUP: Firebase permissions granted: $granted',
                  );

                  if (granted && context.mounted) {
                    debugPrint(
                      '🔔 NOTIFICATION_SETUP: Context still mounted, proceeding with API call...',
                    );
                    // Enable all notification preferences in database
                    try {
                      final apiService = Provider.of<ApiService>(
                        context,
                        listen: false,
                      );
                      debugPrint(
                        '🔔 NOTIFICATION_SETUP: Got ApiService, calling enableAllNotificationPreferences...',
                      );
                      bool success = await apiService
                          .enableAllNotificationPreferences(userId);

                      debugPrint(
                        '🔔 NOTIFICATION_SETUP: API call result: $success',
                      );

                      if (success) {
                        debugPrint(
                          '✅ NOTIFICATION_SETUP: All notification preferences enabled',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Notifications enabled successfully!',
                              ),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } else {
                        debugPrint(
                          '❌ NOTIFICATION_SETUP: Failed to enable notification preferences',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to enable notification preferences',
                              ),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      debugPrint(
                        '❌ NOTIFICATION_SETUP: Error enabling preferences: $e',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error enabling preferences: $e'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  } else {
                    debugPrint(
                      '❌ NOTIFICATION_SETUP: Permissions not granted OR context not mounted',
                    );
                    debugPrint('   - granted: $granted');
                    debugPrint('   - context.mounted: ${context.mounted}');
                  }

                  // Close dialog AFTER async operations complete
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  completed = true;
                },
                child: const Text('Enable Notifications'),
              ),
            ],
          ),
    );

    // Mark that user has seen the notification dialog
    if (completed) {
      await markNotificationDialogSeen(userId);
    }

    return completed;
  }

  /// Check if user has seen the notification dialog (bit 4)
  static Future<bool> hasSeenNotificationDialog(int userId) async {
    try {
      // TODO: Get this from the backend onboarding_state bit 4
      // For now, check local storage as fallback
      return false; // Always show for now until backend integration
    } catch (e) {
      debugPrint(
        '❌ NOTIFICATION_SETUP: Error checking notification dialog bit: $e',
      );
      return false;
    }
  }

  /// Mark that user has seen the notification dialog (set bit 4)
  static Future<void> markNotificationDialogSeen(int userId) async {
    try {
      // TODO: Update backend onboarding_state to set bit 4
      debugPrint(
        '🔔 NOTIFICATION_SETUP: Marked notification dialog seen for user $userId',
      );
    } catch (e) {
      debugPrint(
        '❌ NOTIFICATION_SETUP: Error setting notification dialog bit: $e',
      );
    }
  }

  /// Reset notification dialog status (for testing)
  static Future<void> resetNotificationDialogStatus(int userId) async {
    try {
      // TODO: Clear bit 4 in backend onboarding_state
      debugPrint(
        '🔔 NOTIFICATION_SETUP: Reset notification dialog status for user $userId',
      );
    } catch (e) {
      debugPrint(
        '❌ NOTIFICATION_SETUP: Error resetting notification dialog bit: $e',
      );
    }
  }
}
