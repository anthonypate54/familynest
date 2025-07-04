import 'package:flutter/material.dart';
import '../models/subscription.dart';
import '../models/user.dart';
import 'api_service.dart';

class SubscriptionService {
  final ApiService _apiService;

  SubscriptionService(this._apiService);

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
