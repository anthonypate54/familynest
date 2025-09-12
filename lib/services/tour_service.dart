import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/onboarding/fresh_user_onboarding_screen.dart';
import '../screens/onboarding/invitation_first_onboarding_screen.dart';
import '../screens/onboarding/family_member_onboarding_screen.dart';

enum TourType { freshUser, invitation, familyMember }

class TourService {
  /// Show the specified tour type
  /// Returns the result from the tour (e.g., 'create_family', 'check_invitations', 'explore')
  static Future<String?> showTour(
    BuildContext context,
    int userId,
    String userRole,
    TourType tourType,
  ) async {
    debugPrint('TOUR: Starting ${tourType.name} tour for user $userId');

    Widget tourScreen;
    switch (tourType) {
      case TourType.freshUser:
        tourScreen = FreshUserOnboardingScreen(
          userId: userId,
          userRole: userRole,
        );
        break;
      case TourType.invitation:
        tourScreen = InvitationFirstOnboardingScreen(
          userId: userId,
          userRole: userRole,
        );
        break;
      case TourType.familyMember:
        tourScreen = FamilyMemberOnboardingScreen(
          userId: userId,
          userRole: userRole,
        );
        break;
    }

    // Show the tour and wait for completion
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => tourScreen,
        fullscreenDialog: true,
      ),
    );

    // Mark tour as completed
    await markTourCompleted(userId);

    debugPrint(
      'TOUR: ${tourType.name} tour completed for user $userId with result: $result',
    );
    return result; // Return the actual result from the tour screen
  }

  /// Check if user has seen the tour
  static Future<bool> hasSeenTour(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hasSeenTour_$userId') ?? false;
  }

  /// Mark that user has completed the tour
  static Future<void> markTourCompleted(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenTour_$userId', true);
    debugPrint('TOUR: Marked tour completed for user $userId');
  }

  /// Reset tour status (for testing/debugging)
  static Future<void> resetTourStatus(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hasSeenTour_$userId');
    debugPrint('TOUR: Reset tour status for user $userId');
  }
}
