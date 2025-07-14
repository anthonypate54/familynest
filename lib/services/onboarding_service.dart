import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/onboarding/fresh_user_onboarding_screen.dart';
import '../screens/onboarding/family_member_onboarding_screen.dart';
import '../screens/onboarding/invitation_first_onboarding_screen.dart';
import '../main.dart';

class OnboardingService {
  // Check if user has already completed onboarding tour
  static Future<bool> hasSeenOnboardingTour(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hasSeenOnboardingTour_$userId') ?? false;
  }

  // Mark that user has completed onboarding tour
  static Future<void> markOnboardingTourCompleted(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboardingTour_$userId', true);
    debugPrint('🎯 ONBOARDING: Marked tour completed for user $userId');
  }

  /// Function 1: Fresh user tour (onboarding_state = 0)
  /// Shows 3-page tour → navigates to family creation
  static void takeFreshUserTour(
    BuildContext context,
    int userId,
    String userRole,
  ) {
    debugPrint('🎯 ONBOARDING: Starting fresh user tour for user $userId');

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (context) => FreshUserOnboardingScreen(
                  userId: userId,
                  userRole: userRole,
                ),
            fullscreenDialog: true,
          ),
        )
        .then((_) {
          // After tour completes, mark it as seen and navigate to main app
          markOnboardingTourCompleted(userId);
          debugPrint(
            '🎯 ONBOARDING: Fresh user tour completed, navigating to main app (Family tab)',
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder:
                  (context) => MainAppContainer(
                    userId: userId,
                    userRole: userRole,
                    initialTabIndex: 3, // Family tab index
                  ),
            ),
          );
        });
  }

  /// Function 2: Family member tour (onboarding_state = 2)
  /// Shows family activity overview → navigates to main app
  static void takeFamilyMemberTour(
    BuildContext context,
    int userId,
    String userRole,
  ) {
    debugPrint('🎯 ONBOARDING: Starting family member tour for user $userId');

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (context) => FamilyMemberOnboardingScreen(
                  userId: userId,
                  userRole: userRole,
                ),
            fullscreenDialog: true,
          ),
        )
        .then((_) {
          // After tour completes, navigate to main app
          debugPrint(
            '🎯 ONBOARDING: Family member tour completed, navigating to main app',
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder:
                  (context) =>
                      MainAppContainer(userId: userId, userRole: userRole),
            ),
          );
        });
  }

  /// Function 3: Invitation tour (onboarding_state = 3)
  /// Shows tour → navigates to invitations screen
  static void takeInvitationTour(
    BuildContext context,
    int userId,
    String userRole,
  ) {
    debugPrint('🎯 ONBOARDING: Starting invitation tour for user $userId');

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (context) => InvitationFirstOnboardingScreen(
                  userId: userId,
                  userRole: userRole,
                ),
            fullscreenDialog: true,
          ),
        )
        .then((_) {
          // After tour completes, navigate to main app with Invitations tab selected
          debugPrint(
            '🎯 ONBOARDING: Invitation tour completed, navigating to main app (Invitations tab)',
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder:
                  (context) => MainAppContainer(
                    userId: userId,
                    userRole: userRole,
                    initialTabIndex: 4, // Invitations tab index
                  ),
            ),
          );
        });
  }

  /// Normal processing - go directly to main app
  static void normalFlow(BuildContext context, int userId, String userRole) {
    debugPrint('🎯 ONBOARDING: Normal flow for user $userId');

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (context) => MainAppContainer(userId: userId, userRole: userRole),
      ),
    );
  }

  // Main routing function called from login
  static Future<void> routeAfterLogin(
    BuildContext context,
    int userId,
    String userRole,
    int onboardingState,
  ) async {
    print(
      "🔀 ONBOARDING_SERVICE: Routing user $userId with onboarding_state: $onboardingState",
    );

    // Check individual bits in the onboarding state bitmap
    bool hasMessages = (onboardingState & 1) != 0; // Bit 0
    bool hasDMs = (onboardingState & 2) != 0; // Bit 1
    bool hasFamilyMembership = (onboardingState & 4) != 0; // Bit 2
    bool hasPendingInvitations = (onboardingState & 8) != 0; // Bit 3

    print(
      "🔀 ONBOARDING_SERVICE: Bits - messages:$hasMessages, DMs:$hasDMs, family:$hasFamilyMembership, invitations:$hasPendingInvitations",
    );

    // Check if user has already seen the onboarding tour
    bool hasSeenTour = await hasSeenOnboardingTour(userId);
    print("🔀 ONBOARDING_SERVICE: User $userId hasSeenTour: $hasSeenTour");

    // PRIORITY 1: Fresh users who haven't seen the tour get the tour
    // Fresh users are those with NO activity (messages, DMs, family membership)
    bool isActivityFreshUser = !hasMessages && !hasDMs && !hasFamilyMembership;

    if (isActivityFreshUser && !hasSeenTour) {
      print(
        "🔀 ONBOARDING_SERVICE: Fresh user (no activity, no tour) - taking fresh user tour",
      );
      takeFreshUserTour(context, userId, userRole);
      return;
    }

    // PRIORITY 2: Users with activity or who have seen tour get specialized flows
    if (hasMessages || hasDMs) {
      // User has activity - skip onboarding, go to main app
      print("🔀 ONBOARDING_SERVICE: User has activity - taking normal flow");
      normalFlow(context, userId, userRole);
    } else if (hasFamilyMembership) {
      // User has family membership - go directly to Family Management screen
      print(
        "🔀 ONBOARDING_SERVICE: User has family - going to Family Management screen",
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder:
              (context) => MainAppContainer(
                userId: userId,
                userRole: userRole,
                initialTabIndex: 3, // Family Management tab index
              ),
        ),
      );
    } else if (hasPendingInvitations) {
      // User has pending invitations but no family - show invitation tour
      print("🔀 ONBOARDING_SERVICE: Taking invitation tour");
      takeInvitationTour(context, userId, userRole);
    } else {
      // Fallback - go to main app
      print("🔀 ONBOARDING_SERVICE: Taking normal flow");
      normalFlow(context, userId, userRole);
    }
  }
}
