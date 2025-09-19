import 'package:flutter/material.dart';

enum SubscriptionStatus {
  trial,
  platformTrial,
  active,
  pastDue,
  cancelled,
  expired,
}

enum PaymentMethod { none, creditCard, paypal, applePay, googlePay }

enum Platform { none, apple, google }

class Subscription {
  final int id;
  final int userId;
  final SubscriptionStatus status;
  final DateTime? trialStartDate;
  final DateTime? trialEndDate;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;
  final DateTime? nextBillingDate;
  final double monthlyPrice;
  final PaymentMethod paymentMethod;
  final String? paymentMethodLast4;
  final String? paymentMethodBrand;
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;
  final Platform platform;
  final String? platformTransactionId;
  final bool hasActiveAccess;
  final DateTime createdAt;
  final DateTime updatedAt;

  Subscription({
    required this.id,
    required this.userId,
    required this.status,
    this.trialStartDate,
    this.trialEndDate,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
    this.nextBillingDate,
    this.monthlyPrice = 2.99,
    this.paymentMethod = PaymentMethod.none,
    this.paymentMethodLast4,
    this.paymentMethodBrand,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.platform = Platform.none,
    this.platformTransactionId,
    this.hasActiveAccess = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    // Handle backend API response format
    return Subscription(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? json['userId'] ?? 0,
      status: _parseStatus(json['subscription_status'] ?? json['status']),
      trialStartDate: _parseDate(
        json['trial_start_date'] ?? json['trialStartDate'],
      ),
      trialEndDate: _parseDate(json['trial_end_date'] ?? json['trialEndDate']),
      subscriptionStartDate: _parseDate(
        json['subscription_start_date'] ?? json['subscriptionStartDate'],
      ),
      subscriptionEndDate: _parseDate(
        json['subscription_end_date'] ?? json['subscriptionEndDate'],
      ),
      nextBillingDate: _parseDate(
        json['next_billing_date'] ?? json['nextBillingDate'],
      ),
      monthlyPrice:
          (json['monthly_price'] ?? json['monthlyPrice'] ?? 2.99).toDouble(),
      paymentMethod: _parsePaymentMethod(json['platform']),
      platformTransactionId:
          json['platform_transaction_id'] ?? json['platformTransactionId'],
      platform: _parsePlatform(json['platform']),
      hasActiveAccess:
          json['has_active_access'] ?? json['hasActiveAccess'] ?? false,
      createdAt:
          _parseDate(json['created_at'] ?? json['createdAt']) ?? DateTime.now(),
      updatedAt:
          _parseDate(json['updated_at'] ?? json['updatedAt']) ?? DateTime.now(),
    );
  }

  static SubscriptionStatus _parseStatus(dynamic status) {
    if (status == null) return SubscriptionStatus.trial;

    switch (status.toString().toLowerCase()) {
      case 'trial':
        return SubscriptionStatus.trial;
      case 'platform_trial':
        return SubscriptionStatus.platformTrial;
      case 'active':
        return SubscriptionStatus.active;
      case 'past_due':
        return SubscriptionStatus.pastDue;
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      case 'expired':
        return SubscriptionStatus.expired;
      default:
        return SubscriptionStatus.trial;
    }
  }

  static PaymentMethod _parsePaymentMethod(dynamic platform) {
    if (platform == null) return PaymentMethod.none;

    switch (platform.toString().toUpperCase()) {
      case 'APPLE':
        return PaymentMethod.applePay;
      case 'GOOGLE':
        return PaymentMethod.googlePay;
      default:
        return PaymentMethod.none;
    }
  }

  static Platform _parsePlatform(dynamic platform) {
    if (platform == null) return Platform.none;

    switch (platform.toString().toUpperCase()) {
      case 'APPLE':
        return Platform.apple;
      case 'GOOGLE':
        return Platform.google;
      default:
        return Platform.none;
    }
  }

  static DateTime? _parseDate(dynamic date) {
    if (date == null) return null;

    if (date is int) {
      // Handle timestamp (milliseconds since epoch)
      return DateTime.fromMillisecondsSinceEpoch(date);
    }

    if (date is String) {
      try {
        return DateTime.parse(date);
      } catch (e) {
        return null;
      }
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'status': status.name,
      'trialStartDate': trialStartDate?.toIso8601String(),
      'trialEndDate': trialEndDate?.toIso8601String(),
      'subscriptionStartDate': subscriptionStartDate?.toIso8601String(),
      'subscriptionEndDate': subscriptionEndDate?.toIso8601String(),
      'nextBillingDate': nextBillingDate?.toIso8601String(),
      'monthlyPrice': monthlyPrice,
      'paymentMethod': paymentMethod.name,
      'paymentMethodLast4': paymentMethodLast4,
      'paymentMethodBrand': paymentMethodBrand,
      'stripeCustomerId': stripeCustomerId,
      'stripeSubscriptionId': stripeSubscriptionId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Helper methods
  bool get isInTrial =>
      status == SubscriptionStatus.trial ||
      status == SubscriptionStatus.platformTrial;
  bool get isActive =>
      status == SubscriptionStatus.active ||
      (status == SubscriptionStatus.platformTrial &&
          platformTransactionId != null);
  bool get isPastDue => status == SubscriptionStatus.pastDue;
  bool get isCancelled => status == SubscriptionStatus.cancelled;
  bool get isExpired => status == SubscriptionStatus.expired;

  /// Returns true if user cancelled but still has access until subscription end date
  bool get isCancelledWithAccess {
    if (!isCancelled || subscriptionEndDate == null) return false;
    return DateTime.now().isBefore(subscriptionEndDate!);
  }

  bool get hasPaymentMethod => paymentMethod != PaymentMethod.none;

  int get daysLeftInTrial {
    if (!isInTrial || trialEndDate == null) return 0;
    final now = DateTime.now();
    final difference = trialEndDate!.difference(now).inDays;
    return difference > 0 ? difference : 0;
  }

  int get hoursLeftInTrial {
    if (!isInTrial || trialEndDate == null) return 0;
    final now = DateTime.now();
    final difference = trialEndDate!.difference(now).inHours;
    return difference > 0 ? difference : 0;
  }

  String get trialTimeRemainingText {
    if (!isInTrial || trialEndDate == null) return 'Trial ended';

    final now = DateTime.now();
    final trialDate = DateTime(
      trialEndDate!.year,
      trialEndDate!.month,
      trialEndDate!.day,
    );
    final todayDate = DateTime(now.year, now.month, now.day);

    // Use date-only comparison to match backend logic
    if (trialDate.isAfter(todayDate)) {
      // Trial ends in the future
      final days = trialDate.difference(todayDate).inDays;
      return '$days ${days == 1 ? 'day' : 'days'} left';
    } else if (trialDate.isAtSameMomentAs(todayDate)) {
      // Trial ends today - expires at midnight
      return 'Expires at midnight';
    } else {
      // Trial ended in the past
      return 'Trial expired';
    }
  }

  bool get trialExpired {
    if (!isInTrial || trialEndDate == null) return false;

    // Use date-only comparison to match backend logic
    final now = DateTime.now();
    final trialDate = DateTime(
      trialEndDate!.year,
      trialEndDate!.month,
      trialEndDate!.day,
    );
    final todayDate = DateTime(now.year, now.month, now.day);

    return trialDate.isBefore(todayDate);
  }

  String get statusDisplayText {
    switch (status) {
      case SubscriptionStatus.trial:
      case SubscriptionStatus.platformTrial:
        // Check if trial has actually expired
        if (trialExpired) {
          return 'Trial Expired';
        }
        return 'Free Trial';
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.pastDue:
        return 'Past Due';
      case SubscriptionStatus.cancelled:
        return 'Cancelled';
      case SubscriptionStatus.expired:
        return 'Expired';
    }
  }

  Color get statusColor {
    switch (status) {
      case SubscriptionStatus.trial:
      case SubscriptionStatus.platformTrial:
        // Show red for expired trials
        if (trialExpired) {
          return Colors.red;
        }
        return Colors.blue;
      case SubscriptionStatus.active:
        return Colors.green;
      case SubscriptionStatus.pastDue:
        return Colors.orange;
      case SubscriptionStatus.cancelled:
        return Colors.red;
      case SubscriptionStatus.expired:
        return Colors.grey;
    }
  }

  String get paymentMethodDisplayText {
    // For platform-managed subscriptions, show the platform
    if (platform == Platform.apple) {
      return 'Apple Pay';
    }
    if (platform == Platform.google) {
      return 'Google Pay';
    }

    if (paymentMethod == PaymentMethod.none) return 'No payment method';

    String methodName;
    switch (paymentMethod) {
      case PaymentMethod.creditCard:
        methodName = paymentMethodBrand ?? 'Card';
        break;
      case PaymentMethod.paypal:
        methodName = 'PayPal';
        break;
      case PaymentMethod.applePay:
        methodName = 'Apple Pay';
        break;
      case PaymentMethod.googlePay:
        methodName = 'Google Pay';
        break;
      default:
        methodName = 'Unknown';
    }

    if (paymentMethodLast4 != null) {
      return '$methodName •••• $paymentMethodLast4';
    }
    return methodName;
  }

  String get priceDisplayText => '\$${monthlyPrice.toStringAsFixed(2)}/month';

  /// CRITICAL: Single source of truth for subscription access
  /// This method combines all validation logic to determine if user has access
  bool get shouldHaveAccess {
    final now = DateTime.now();

    // ALWAYS trust backend's hasActiveAccess field if available
    // This is the authoritative source from server-side validation
    if (hasActiveAccess) {
      return true;
    }

    // Secondary validation for edge cases where backend field might be stale
    switch (status) {
      case SubscriptionStatus.active:
        // Active paid subscriptions get access (platform-managed)
        return true;

      case SubscriptionStatus.trial:
      case SubscriptionStatus.platformTrial:
        // Check trial hasn't expired
        if (trialEndDate == null) return false;
        return now.isBefore(trialEndDate!);

      case SubscriptionStatus.expired:
        return false;

      case SubscriptionStatus.cancelled:
        // Cancelled users keep access until their paid period ends
        if (subscriptionEndDate == null) return false;
        return now.isBefore(subscriptionEndDate!);

      case SubscriptionStatus.pastDue:
        // Past due might still have grace period - trust backend
        return hasActiveAccess;
    }
  }

  // Create a default trial subscription for new users
  static Subscription createTrial(int userId) {
    final now = DateTime.now();
    final trialEnd = now.add(const Duration(days: 30));

    return Subscription(
      id: 0, // Will be set by backend
      userId: userId,
      status: SubscriptionStatus.trial,
      trialStartDate: now,
      trialEndDate: trialEnd,
      monthlyPrice: 2.99,
      paymentMethod: PaymentMethod.none,
      createdAt: now,
      updatedAt: now,
    );
  }

  // Copy with updated fields
  Subscription copyWith({
    int? id,
    int? userId,
    SubscriptionStatus? status,
    DateTime? trialStartDate,
    DateTime? trialEndDate,
    DateTime? subscriptionStartDate,
    DateTime? subscriptionEndDate,
    DateTime? nextBillingDate,
    double? monthlyPrice,
    PaymentMethod? paymentMethod,
    String? paymentMethodLast4,
    String? paymentMethodBrand,
    String? stripeCustomerId,
    String? stripeSubscriptionId,
    Platform? platform,
    String? platformTransactionId,
    bool? hasActiveAccess,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Subscription(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      trialStartDate: trialStartDate ?? this.trialStartDate,
      trialEndDate: trialEndDate ?? this.trialEndDate,
      subscriptionStartDate:
          subscriptionStartDate ?? this.subscriptionStartDate,
      subscriptionEndDate: subscriptionEndDate ?? this.subscriptionEndDate,
      nextBillingDate: nextBillingDate ?? this.nextBillingDate,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentMethodLast4: paymentMethodLast4 ?? this.paymentMethodLast4,
      paymentMethodBrand: paymentMethodBrand ?? this.paymentMethodBrand,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      stripeSubscriptionId: stripeSubscriptionId ?? this.stripeSubscriptionId,
      platform: platform ?? this.platform,
      platformTransactionId:
          platformTransactionId ?? this.platformTransactionId,
      hasActiveAccess: hasActiveAccess ?? this.hasActiveAccess,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
