import 'dart:io' as io;

/// Centralized helper for platform-specific text and subscription logic
class PlatformTextHelper {
  /// Get the current platform's store name
  static String getStoreName() {
    return io.Platform.isIOS ? 'App Store' : 'Google Play';
  }

  /// Get subscription button text
  static String getSubscribeButtonText() {
    return 'Subscribe via ${getStoreName()}';
  }

  /// Get manage subscription text
  static String getManageSubscriptionText() {
    return 'Your subscription is managed through ${getStoreName()}.';
  }

  /// Format transaction platform for display (handles database values)
  static String formatTransactionPlatform(String? dbPlatform) {
    if (dbPlatform == null) return 'Unknown';

    switch (dbPlatform.toUpperCase()) {
      case 'GOOGLE':
        return 'Google Play';
      case 'APPLE':
        return 'App Store';
      default:
        return dbPlatform;
    }
  }

  /// Get subscription info box text
  static String getSubscriptionInfoText() {
    return 'Subscription managed through ${getStoreName()}';
  }

  /// Get instructions for managing subscription
  static String getManageInstructions() {
    if (io.Platform.isIOS) {
      return 'To manage your subscription:\n'
          '• Open Settings on your device\n'
          '• Tap your name at the top\n'
          '• Tap Subscriptions\n'
          '• Select FamilyNest';
    } else {
      return 'To manage your subscription:\n'
          '• Open Google Play Store\n'
          '• Tap Menu (☰)\n'
          '• Tap Subscriptions\n'
          '• Select FamilyNest';
    }
  }

  /// Get cancel warning text
  static String getCancelWarningText() {
    return io.Platform.isIOS
        ? 'Note: This will only cancel in our system. You must also cancel through App Store Settings to stop billing.'
        : 'Note: This will only cancel in our system. You must also cancel through Google Play to stop billing.';
  }
}




