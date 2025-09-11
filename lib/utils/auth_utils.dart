import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../screens/login_screen.dart';
import 'package:provider/provider.dart';
import '../providers/message_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

class AuthUtils {
  /// Show confirmation dialog and handle logout if confirmed
  /// Returns true if the user was logged out, false otherwise
  static Future<bool> showLogoutConfirmation(
    BuildContext context,
    ApiService apiService,
  ) async {
    // Show confirmation dialog
    bool confirmLogout =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Confirm Logout'),
                content: const Text('Are you sure you want to log out?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Logout'),
                  ),
                ],
              ),
        ) ??
        false;

    if (confirmLogout) {
      debugPrint('Logging out...');

      // Show a loading dialog to prevent interaction during logout
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const Dialog(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text("Logging out..."),
                  ],
                ),
              ),
            );
          },
        );
      }

      // Clear authentication data
      await apiService.logout();

      // Clear message cache to prevent data leaks between users
      if (context.mounted) {
        try {
          final messageProvider = Provider.of<MessageProvider>(
            context,
            listen: false,
          );
          messageProvider.clear();
          debugPrint('✅ Cleared MessageProvider cache');
        } catch (e) {
          debugPrint('⚠️ Could not clear MessageProvider: $e');
        }
      }

      // Verify the token was actually cleared
      final prefs = await SharedPreferences.getInstance();
      final hasToken = prefs.containsKey('auth_token');
      final hasUserId = prefs.containsKey('user_id');

      if (hasToken || hasUserId) {
        debugPrint(
          '⚠️ WARNING: Some auth data still exists after logout, forcing cleanup',
        );
        // Force manual cleanup if needed
        await prefs.remove('auth_token');
        await prefs.remove('auth_token_backup');
        await prefs.remove('user_id');
        await prefs.remove('user_role');
        await prefs.remove('is_logged_in');
        await prefs.remove('login_time');
      }

      // Short delay to ensure all pending operations complete
      await Future.delayed(const Duration(milliseconds: 300));

      if (context.mounted) {
        // Dismiss the loading dialog
        Navigator.of(context).pop();

        // Use Navigator.pushAndRemoveUntil to properly clear the navigation stack
        // and ensure a fresh Login screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false, // This removes all previous routes
        );
      }
      return true;
    }

    return false;
  }
}
