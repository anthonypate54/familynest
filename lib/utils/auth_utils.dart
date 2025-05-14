import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../screens/login_screen.dart';
import '../utils/page_transitions.dart';

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
      await apiService.logout();
      if (context.mounted) {
        // Use Navigator.pushAndRemoveUntil to clear the navigation stack
        slidePushAndRemoveUntil(
          context,
          LoginScreen(apiService: apiService),
          (route) => false, // This predicate removes all routes
        );
      }
      return true;
    }

    return false;
  }
}
