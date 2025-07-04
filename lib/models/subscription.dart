import 'package:flutter/material.dart';

enum SubscriptionStatus { trial, active, pastDue, cancelled, expired }

enum PaymentMethod { none, creditCard, paypal, applePay, googlePay }

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
    this.monthlyPrice = 4.99,
    this.paymentMethod = PaymentMethod.none,
    this.paymentMethodLast4,
    this.paymentMethodBrand,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'],
      userId: json['userId'],
      status: SubscriptionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SubscriptionStatus.trial,
      ),
      trialStartDate:
          json['trialStartDate'] != null
              ? DateTime.parse(json['trialStartDate'])
              : null,
      trialEndDate:
          json['trialEndDate'] != null
              ? DateTime.parse(json['trialEndDate'])
              : null,
      subscriptionStartDate:
          json['subscriptionStartDate'] != null
              ? DateTime.parse(json['subscriptionStartDate'])
              : null,
      subscriptionEndDate:
          json['subscriptionEndDate'] != null
              ? DateTime.parse(json['subscriptionEndDate'])
              : null,
      nextBillingDate:
          json['nextBillingDate'] != null
              ? DateTime.parse(json['nextBillingDate'])
              : null,
      monthlyPrice: json['monthlyPrice']?.toDouble() ?? 4.99,
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) => e.name == json['paymentMethod'],
        orElse: () => PaymentMethod.none,
      ),
      paymentMethodLast4: json['paymentMethodLast4'],
      paymentMethodBrand: json['paymentMethodBrand'],
      stripeCustomerId: json['stripeCustomerId'],
      stripeSubscriptionId: json['stripeSubscriptionId'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
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
  bool get isInTrial => status == SubscriptionStatus.trial;
  bool get isActive => status == SubscriptionStatus.active;
  bool get isPastDue => status == SubscriptionStatus.pastDue;
  bool get isCancelled => status == SubscriptionStatus.cancelled;
  bool get isExpired => status == SubscriptionStatus.expired;

  bool get hasPaymentMethod => paymentMethod != PaymentMethod.none;

  int get daysLeftInTrial {
    if (!isInTrial || trialEndDate == null) return 0;
    final now = DateTime.now();
    final difference = trialEndDate!.difference(now).inDays;
    return difference > 0 ? difference : 0;
  }

  bool get trialExpired {
    if (!isInTrial || trialEndDate == null) return false;
    return DateTime.now().isAfter(trialEndDate!);
  }

  String get statusDisplayText {
    switch (status) {
      case SubscriptionStatus.trial:
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
      monthlyPrice: 4.99,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
