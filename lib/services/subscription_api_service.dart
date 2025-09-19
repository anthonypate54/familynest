import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Dedicated service for subscription-related API calls
/// Follows single responsibility principle - only handles subscription endpoints
class SubscriptionApiService {
  static const String _logTag = '💳 SubscriptionAPI';

  final ApiService _apiService;

  SubscriptionApiService(this._apiService);

  String get _baseUrl => _apiService.baseUrl;
  String? get _token => _apiService.token;

  /// Get user's subscription status and details
  Future<Map<String, dynamic>?> getSubscriptionStatus() async {
    if (_token == null) {
      debugPrint('$_logTag: ❌ No token available for subscription status');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/subscription/status'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint(
        '$_logTag: 📊 Subscription status response: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
          '$_logTag: ✅ Subscription status retrieved: ${data['subscription_status']}',
        );
        return data;
      } else {
        debugPrint(
          '$_logTag: ❌ Failed to get subscription status: ${response.statusCode}',
        );
        debugPrint('$_logTag: Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Exception getting subscription status: $e');
      return null;
    }
  }

  /// Get user's payment history
  Future<Map<String, dynamic>?> getPaymentHistory() async {
    if (_token == null) {
      debugPrint('$_logTag: ❌ No token available for payment history');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/subscription/history'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint(
        '$_logTag: 💰 Payment history response: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
          '$_logTag: ✅ Payment history retrieved: ${data['transactions']?.length ?? 0} transactions',
        );
        return data;
      } else {
        debugPrint(
          '$_logTag: ❌ Failed to get payment history: ${response.statusCode}',
        );
        debugPrint('$_logTag: Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Exception getting payment history: $e');
      return null;
    }
  }

  /// Verify Apple In-App Purchase
  Future<Map<String, dynamic>?> verifyApplePurchase({
    required String receiptData,
    required String productId,
  }) async {
    if (_token == null) {
      debugPrint('$_logTag: ❌ No token available for Apple verification');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/subscription/verify-apple'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'receipt_data': receiptData,
          'product_id': productId,
        }),
      );

      debugPrint(
        '$_logTag: 🍎 Apple verification response: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
          '$_logTag: ✅ Apple purchase verified: ${data['transaction_id']}',
        );
        return data;
      } else {
        debugPrint(
          '$_logTag: ❌ Failed to verify Apple purchase: ${response.statusCode}',
        );
        debugPrint('$_logTag: Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Exception verifying Apple purchase: $e');
      return null;
    }
  }

  /// Verify Google Play Purchase
  Future<Map<String, dynamic>?> verifyGooglePurchase({
    required String purchaseToken,
    required String productId,
  }) async {
    if (_token == null) {
      debugPrint('$_logTag: ❌ No token available for Google verification');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/subscription/verify-google'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'purchase_token': purchaseToken,
          'product_id': productId,
        }),
      );

      debugPrint(
        '$_logTag: 📱 Google verification response: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
          '$_logTag: ✅ Google purchase verified: ${data['transaction_id']}',
        );
        return data;
      } else {
        debugPrint(
          '$_logTag: ❌ Failed to verify Google purchase: ${response.statusCode}',
        );
        debugPrint('$_logTag: Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Exception verifying Google purchase: $e');
      return null;
    }
  }

  /// Cancel user's subscription
  Future<bool> cancelSubscription() async {
    if (_token == null) {
      debugPrint(
        '$_logTag: ❌ No token available for subscription cancellation',
      );
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/subscription/cancel'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint(
        '$_logTag: ❌ Cancel subscription response: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('$_logTag: ✅ Subscription cancelled: ${data['message']}');
        return true;
      } else {
        debugPrint(
          '$_logTag: ❌ Failed to cancel subscription: ${response.statusCode}',
        );
        debugPrint('$_logTag: Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Exception cancelling subscription: $e');
      return false;
    }
  }
}
