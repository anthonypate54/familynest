import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/subscription.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'subscription_api_service.dart';

class SubscriptionService {
  static const String _logTag = '🔒 SubscriptionService';

  final ApiService _apiService;
  late final SubscriptionApiService _subscriptionApi;

  SubscriptionService(this._apiService) {
    _subscriptionApi = SubscriptionApiService(_apiService);
  }

  /// CRITICAL: Main method to check if user has access to the app
  /// Returns true if user can use the app, false if they need to subscribe
  Future<bool> validateUserAccess(User? user) async {
    if (user == null) {
      debugPrint('$_logTag: No user provided - denying access');
      return false;
    }

    debugPrint('$_logTag: Validating access for user ${user.username}');

    // First check: Do we have recent subscription data?
    if (user.subscription != null) {
      final localAccess = user.subscription!.shouldHaveAccess;
      debugPrint('$_logTag: Local subscription check: $localAccess');

      // If local data says they have access, trust it (avoid unnecessary API calls)
      if (localAccess) {
        debugPrint('$_logTag: ✅ Local validation passed - granting access');
        return true;
      }
    }

    // Second check: Query backend for authoritative answer
    debugPrint('$_logTag: Local check failed or no data - querying backend...');
    try {
      final subscriptionData = await _subscriptionApi.getSubscriptionStatus();

      if (subscriptionData == null) {
        debugPrint('$_logTag: ❌ Backend returned null - denying access');
        return false;
      }

      final hasAccess = subscriptionData['has_active_access'] ?? false;
      debugPrint('$_logTag: Backend says has_active_access: $hasAccess');

      // Log the full subscription state for debugging
      debugPrint('$_logTag: Backend subscription state:');
      debugPrint('  - Status: ${subscriptionData['subscription_status']}');
      debugPrint('  - Trial End: ${subscriptionData['trial_end_date']}');
      debugPrint(
        '  - Subscription End: ${subscriptionData['subscription_end_date']}',
      );
      debugPrint('  - Has Active Access: $hasAccess');

      return hasAccess;
    } catch (e) {
      debugPrint('$_logTag: ❌ Error checking backend subscription: $e');

      // IMPORTANT: On network error, be conservative
      // If we can't verify subscription, deny access rather than risk giving free access
      return false;
    }
  }

  /// Log subscription state for debugging purposes
  void logSubscriptionState(User? user, String context) {
    if (!kDebugMode) return; // Only log in debug builds

    debugPrint('$_logTag: ==========================================');
    debugPrint('$_logTag: Subscription State ($context)');
    debugPrint('$_logTag: ==========================================');

    if (user == null) {
      debugPrint('$_logTag: User: NULL');
      return;
    }

    debugPrint('$_logTag: User: ${user.username} (ID: ${user.id})');

    if (user.subscription == null) {
      debugPrint('$_logTag: Subscription: NULL');
      return;
    }

    final sub = user.subscription!;
    debugPrint('$_logTag: Subscription Status: ${sub.status.name}');
    debugPrint('$_logTag: Trial End: ${sub.trialEndDate}');
    debugPrint('$_logTag: Is In Trial: ${sub.isInTrial}');
    debugPrint('$_logTag: Should Have Access: ${sub.shouldHaveAccess}');
    debugPrint('$_logTag: Has Active Access: ${sub.hasActiveAccess}');
    debugPrint('$_logTag: ==========================================');
  }

  // Get user's subscription status
  Future<Subscription?> getUserSubscription(int userId) async {
    try {
      // TODO: Replace with actual API call when backend is ready
      // For now, return a mock trial subscription
      return Subscription.createTrial(userId);
    } catch (e) {
      debugPrint('Error fetching subscription: $e');
      return null;
    }
  }

  // Start a free trial for a new user
  Future<Subscription?> startFreeTrial(int userId) async {
    try {
      // TODO: API call to backend to create trial subscription
      final subscription = Subscription.createTrial(userId);

      // In a real implementation, this would call:
      // final response = await _apiService.createSubscription(userId, subscription.toJson());
      // return Subscription.fromJson(response);

      debugPrint('Started free trial for user $userId');
      return subscription;
    } catch (e) {
      debugPrint('Error starting trial: $e');
      return null;
    }
  }

  // Check if user's trial has expired
  bool isTrialExpired(Subscription subscription) {
    return subscription.trialExpired;
  }

  // Get days remaining in trial
  int getTrialDaysRemaining(Subscription subscription) {
    return subscription.daysLeftInTrial;
  }

  // Check if user has access to premium features
  bool hasAccessToPremiumFeatures(User user) {
    if (user.subscription == null) return false;

    final subscription = user.subscription!;

    // Allow access during trial or if subscription is active
    return subscription.isInTrial || subscription.isActive;
  }

  // Add payment method (Stripe integration placeholder)
  Future<bool> addPaymentMethod(
    int userId,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      // TODO: Integrate with Stripe
      // 1. Create Stripe customer if needed
      // 2. Add payment method to Stripe
      // 3. Update subscription in backend

      debugPrint('Adding payment method for user $userId');

      // Mock success for now
      await Future.delayed(const Duration(seconds: 1));
      return true;
    } catch (e) {
      debugPrint('Error adding payment method: $e');
      return false;
    }
  }

  // Upgrade from trial to paid subscription
  Future<Subscription?> upgradeSubscription(
    int userId,
    String paymentMethodId,
  ) async {
    try {
      // TODO: Stripe integration
      // 1. Create Stripe subscription
      // 2. Update subscription in backend
      // 3. Return updated subscription

      debugPrint('Upgrading subscription for user $userId');

      final now = DateTime.now();
      final subscription = Subscription(
        id: 1, // Would come from backend
        userId: userId,
        status: SubscriptionStatus.active,
        trialStartDate: now.subtract(const Duration(days: 15)), // Example
        trialEndDate: now.add(const Duration(days: 15)), // Example
        subscriptionStartDate: now,
        nextBillingDate: now.add(const Duration(days: 30)),
        monthlyPrice: 4.99,
        paymentMethod: PaymentMethod.creditCard,
        paymentMethodLast4: '4242',
        paymentMethodBrand: 'Visa',
        stripeCustomerId: 'cus_example123',
        stripeSubscriptionId: 'sub_example123',
        createdAt: now,
        updatedAt: now,
      );

      return subscription;
    } catch (e) {
      debugPrint('Error upgrading subscription: $e');
      return null;
    }
  }

  // Cancel subscription
  Future<bool> cancelSubscription(int userId) async {
    try {
      // TODO: Stripe integration
      // 1. Cancel Stripe subscription
      // 2. Update subscription status in backend

      debugPrint('Cancelling subscription for user $userId');

      // Mock success for now
      await Future.delayed(const Duration(seconds: 1));
      return true;
    } catch (e) {
      debugPrint('Error cancelling subscription: $e');
      return false;
    }
  }

  // Update payment method
  Future<bool> updatePaymentMethod(
    int userId,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      // TODO: Stripe integration
      // 1. Update payment method in Stripe
      // 2. Update subscription in backend

      debugPrint('Updating payment method for user $userId');

      // Mock success for now
      await Future.delayed(const Duration(seconds: 1));
      return true;
    } catch (e) {
      debugPrint('Error updating payment method: $e');
      return false;
    }
  }

  // Get billing history
  Future<List<Map<String, dynamic>>> getBillingHistory(int userId) async {
    try {
      // TODO: API call to get billing history
      // Mock data for now
      return [
        {
          'id': '1',
          'date':
              DateTime.now()
                  .subtract(const Duration(days: 30))
                  .toIso8601String(),
          'amount': 4.99,
          'status': 'paid',
          'description': 'FamilyNest Premium - Monthly',
        },
        {
          'id': '2',
          'date':
              DateTime.now()
                  .subtract(const Duration(days: 60))
                  .toIso8601String(),
          'amount': 4.99,
          'status': 'paid',
          'description': 'FamilyNest Premium - Monthly',
        },
      ];
    } catch (e) {
      debugPrint('Error fetching billing history: $e');
      return [];
    }
  }

  // Check if user needs to add payment method
  bool needsPaymentMethod(User user) {
    if (user.subscription == null) return false;

    final subscription = user.subscription!;

    // If in trial and trial is ending soon (within 3 days), prompt for payment
    if (subscription.isInTrial && subscription.daysLeftInTrial <= 3) {
      return !subscription.hasPaymentMethod;
    }

    return false;
  }

  // Get subscription status message for UI
  String getSubscriptionStatusMessage(User user) {
    if (user.subscription == null) {
      return 'Start your 30-day free trial today!';
    }

    final subscription = user.subscription!;

    if (subscription.isInTrial) {
      final daysLeft = subscription.daysLeftInTrial;
      if (daysLeft > 1) {
        return 'Your free trial ends in $daysLeft days';
      } else if (daysLeft == 1) {
        return 'Your free trial ends tomorrow';
      } else {
        return 'Your free trial has ended';
      }
    }

    if (subscription.isActive) {
      return 'Your subscription is active';
    }

    if (subscription.isPastDue) {
      return 'Payment failed - please update your payment method';
    }

    if (subscription.isCancelled) {
      return 'Your subscription has been cancelled';
    }

    return 'Subscription status unknown';
  }

  // Calculate prorated amount for mid-cycle upgrades
  double calculateProratedAmount(
    DateTime billingCycleStart,
    DateTime upgradeDate,
  ) {
    final totalDays = 30; // Monthly billing
    final remainingDays =
        billingCycleStart
            .add(Duration(days: totalDays))
            .difference(upgradeDate)
            .inDays;
    final dailyRate = 4.99 / totalDays;

    return dailyRate * remainingDays;
  }

  // Stripe webhook handler (placeholder)
  Future<void> handleStripeWebhook(Map<String, dynamic> event) async {
    try {
      final eventType = event['type'] as String;

      switch (eventType) {
        case 'customer.subscription.created':
          // Handle subscription creation
          break;
        case 'customer.subscription.updated':
          // Handle subscription updates
          break;
        case 'customer.subscription.deleted':
          // Handle subscription cancellation
          break;
        case 'invoice.payment_succeeded':
          // Handle successful payment
          break;
        case 'invoice.payment_failed':
          // Handle failed payment
          break;
        default:
          debugPrint('Unhandled Stripe webhook event: $eventType');
      }
    } catch (e) {
      debugPrint('Error handling Stripe webhook: $e');
    }
  }

  // Validate subscription access for specific features
  bool canAccessFeature(User user, String featureName) {
    if (!hasAccessToPremiumFeatures(user)) {
      return false;
    }

    // Define feature access rules
    switch (featureName) {
      case 'unlimited_storage':
      case 'hd_video':
      case 'multiple_families':
      case 'ad_free':
        return true;
      default:
        return false;
    }
  }

  // Show appropriate subscription prompt
  void showSubscriptionPrompt(BuildContext context, User user, String feature) {
    if (user.subscription == null || user.subscription!.isExpired) {
      _showTrialPrompt(context, feature);
    } else if (user.subscription!.isInTrial &&
        !user.subscription!.hasPaymentMethod) {
      _showAddPaymentPrompt(context, user.subscription!.daysLeftInTrial);
    }
  }

  void _showTrialPrompt(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Start Free Trial'),
            content: Text(
              '$feature requires FamilyNest Premium. Start your 30-day free trial now!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Maybe Later'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navigate to subscription setup
                },
                child: const Text('Start Trial'),
              ),
            ],
          ),
    );
  }

  void _showAddPaymentPrompt(BuildContext context, int daysLeft) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Payment Method'),
            content: Text(
              daysLeft > 1
                  ? 'Your trial ends in $daysLeft days. Add a payment method to continue using FamilyNest Premium.'
                  : 'Your trial ends soon. Add a payment method to avoid interruption.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Remind Later'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navigate to payment method setup
                },
                child: const Text('Add Payment'),
              ),
            ],
          ),
    );
  }
}
