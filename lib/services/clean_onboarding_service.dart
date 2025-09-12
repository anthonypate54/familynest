import 'package:flutter/material.dart';
import 'tour_service.dart';
import 'notification_setup_service.dart';
import '../main.dart';

class CleanOnboardingService {
  /// Main routing function - clean switch based on onboarding state bits
  static Future<void> routeAfterLogin(
    BuildContext context,
    int userId,
    String userRole,
    int onboardingState,
  ) async {
    debugPrint(
      '🔀 CLEAN_ONBOARDING: Routing user $userId with state: $onboardingState',
    );

    // Extract bits from onboarding state
    bool hasMessages = (onboardingState & 1) != 0; // Bit 0
    bool hasDMs = (onboardingState & 2) != 0; // Bit 1
    bool hasFamilyMembership = (onboardingState & 4) != 0; // Bit 2
    bool hasPendingInvitations = (onboardingState & 8) != 0; // Bit 3
    bool hasSeenNotificationDialog = (onboardingState & 16) != 0; // Bit 4 (NEW)

    debugPrint(
      '🔀 CLEAN_ONBOARDING: Bits - messages:$hasMessages, DMs:$hasDMs, family:$hasFamilyMembership, invitations:$hasPendingInvitations, notifications:$hasSeenNotificationDialog',
    );

    // Clean switch statement based on user state
    if (!hasMessages && !hasDMs && !hasFamilyMembership) {
      // Fresh user cases - always show fresh user tour
      if (hasSeenNotificationDialog) {
        await _handleFreshUserWithNotifications(context, userId, userRole);
      } else {
        await _handleFreshUser(context, userId, userRole);
      }
    } else if (hasPendingInvitations && !hasMessages && !hasDMs) {
      // User with family membership but pending invites (invited to additional families)
      await _handleFreshUserWithInvite(
        context,
        userId,
        userRole,
        hasSeenNotificationDialog,
      );
    } else if (hasFamilyMembership && !hasMessages && !hasDMs) {
      // Family member without activity
      await _handleFamilyMember(context, userId, userRole);
    } else {
      // User with activity - go to main app
      await _handleExistingUser(context, userId, userRole);
    }
  }

  /// Case: Fresh user (no activity, no notification bit set)
  static Future<void> _handleFreshUser(
    BuildContext context,
    int userId,
    String userRole,
  ) async {
    debugPrint('🔀 FRESH_USER: Starting tour + notification setup');

    // 1. Show the tour and get result
    final tourResult = await TourService.showTour(
      context,
      userId,
      userRole,
      TourType.freshUser,
    );

    // 2. Handle notification setup REGARDLESS of tour choice
    debugPrint('🔀 FRESH_USER: Tour completed, starting notification setup');
    if (context.mounted) {
      await NotificationSetupService.handleNotificationSetup(
        context,
        userId,
        userRole,
      );
    }

    // 3. Handle different tour results for navigation
    if (!context.mounted) return;

    if (tourResult == 'create_family') {
      // User wants to create family - go to family tab
      debugPrint('🔀 FRESH_USER: User wants to create family');
      navigateToMainApp(context, userId, userRole, initialTab: 3); // Family tab
    } else if (tourResult == 'check_invitations') {
      // User wants to check invitations - go to invitations tab
      debugPrint('🔀 FRESH_USER: User wants to check invitations');
      navigateToMainApp(
        context,
        userId,
        userRole,
        initialTab: 4,
      ); // Invitations tab
    } else {
      // Normal completion - go to main app
      navigateToMainApp(context, userId, userRole, initialTab: 3); // Family tab
    }
  }

  /// Case: Fresh user with notification bit set (skip notification dialog)
  static Future<void> _handleFreshUserWithNotifications(
    BuildContext context,
    int userId,
    String userRole,
  ) async {
    debugPrint(
      '🔀 FRESH_USER_WITH_NOTIFICATIONS: Starting tour, skipping notifications',
    );

    // 1. Show the tour
    await TourService.showTour(context, userId, userRole, TourType.freshUser);

    // 2. Skip notification setup (already done)
    debugPrint('🔔 Skipping notification setup - already completed');

    // 3. Go to main app
    if (context.mounted) {
      navigateToMainApp(context, userId, userRole, initialTab: 3); // Family tab
    }
  }

  /// Case: Fresh user with invite (must take invite tour + notifications)
  static Future<void> _handleFreshUserWithInvite(
    BuildContext context,
    int userId,
    String userRole,
    bool hasSeenNotificationDialog,
  ) async {
    debugPrint(
      '🔀 FRESH_USER_WITH_INVITE: Starting invite tour + notification setup',
    );

    // 1. Show the invite tour
    await TourService.showTour(context, userId, userRole, TourType.invitation);

    // 2. Handle notification setup if not seen
    if (!hasSeenNotificationDialog && context.mounted) {
      await NotificationSetupService.handleNotificationSetup(
        context,
        userId,
        userRole,
      );
    }

    // 3. Go to invites screen
    if (context.mounted) {
      navigateToMainApp(
        context,
        userId,
        userRole,
        initialTab: 4,
      ); // Invitations tab
    }
  }

  /// Case: Family member (has family, no activity)
  static Future<void> _handleFamilyMember(
    BuildContext context,
    int userId,
    String userRole,
  ) async {
    debugPrint('🔀 FAMILY_MEMBER: Starting family member tour');

    // 1. Show family member tour
    await TourService.showTour(
      context,
      userId,
      userRole,
      TourType.familyMember,
    );

    // 2. Go to main app
    if (context.mounted) {
      navigateToMainApp(context, userId, userRole, initialTab: 0); // Feed tab
    }
  }

  /// Case: Existing user (has activity)
  static Future<void> _handleExistingUser(
    BuildContext context,
    int userId,
    String userRole,
  ) async {
    debugPrint('🔀 EXISTING_USER: Going directly to main app');

    // Go directly to main app - no tour needed
    navigateToMainApp(context, userId, userRole, initialTab: 0); // Feed tab
  }

  /// Navigate to main app with clean parameters
  static void navigateToMainApp(
    BuildContext context,
    int userId,
    String userRole, {
    int initialTab = 0,
  }) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (context) => MainAppContainer(
              userId: userId,
              userRole: userRole,
              initialTabIndex: initialTab,
              // No more skipNotificationCheck or skipAuthCheck flags!
            ),
      ),
    );
  }

  /// Force show tour (for manual triggering)
  static Future<void> showTourManually(
    BuildContext context,
    int userId,
    String userRole,
    TourType tourType,
  ) async {
    debugPrint(
      'MANUAL_TOUR: Showing ${tourType.name} tour for user $userId',
    );
    await TourService.showTour(context, userId, userRole, tourType);
  }

  /// Fallback for edge cases - go directly to main app
  static void normalFlow(BuildContext context, int userId, String userRole) {
    debugPrint('🔀 NORMAL_FLOW: Going directly to main app for user $userId');
    navigateToMainApp(context, userId, userRole, initialTab: 0);
  }
}
