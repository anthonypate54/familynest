import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'subscription_api_service.dart';

/// Professional in-app purchase service for FamilyNest subscriptions
/// Handles both Google Play and Apple App Store purchases
class PurchaseService {
  static const String _logTag = '💳 PurchaseService';

  // Product IDs for both platforms
  static const String _monthlySubscriptionId = 'familynest_premium_monthly';
  static const Set<String> _productIds = {_monthlySubscriptionId};

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final SubscriptionApiService _subscriptionApi;

  // Purchase state
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  List<PurchaseDetails> _purchases = [];

  // Callbacks
  Function(bool success, String? error)? _onPurchaseComplete;

  PurchaseService(this._subscriptionApi);

  /// Initialize the purchase service
  Future<bool> initialize() async {
    try {
      debugPrint('$_logTag: Initializing IAP service...');

      // Check if IAP is available
      _isAvailable = await _inAppPurchase.isAvailable();
      if (!_isAvailable) {
        debugPrint('$_logTag: ❌ IAP not available on this device');
        return false;
      }

      debugPrint('$_logTag: ✅ IAP available, loading products...');

      // Load products
      final ProductDetailsResponse productDetailResponse = await _inAppPurchase
          .queryProductDetails(_productIds);

      if (productDetailResponse.error != null) {
        debugPrint(
          '$_logTag: ❌ Error loading products: ${productDetailResponse.error}',
        );
        return false;
      }

      _products = productDetailResponse.productDetails;
      debugPrint('$_logTag: ✅ Loaded ${_products.length} products');

      for (final product in _products) {
        debugPrint(
          '$_logTag: Product: ${product.id} - ${product.price} - ${product.title}',
        );
      }

      // Set up purchase stream listener
      _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdated,
        onDone: () => debugPrint('$_logTag: Purchase stream closed'),
        onError:
            (error) => debugPrint('$_logTag: ❌ Purchase stream error: $error'),
      );

      // Check for pending purchases
      await _checkPendingPurchases();

      return true;
    } catch (e) {
      debugPrint('$_logTag: ❌ Initialization error: $e');
      return false;
    }
  }

  /// Get monthly subscription product details
  ProductDetails? get monthlySubscription {
    try {
      return _products.firstWhere(
        (product) => product.id == _monthlySubscriptionId,
      );
    } catch (e) {
      debugPrint('$_logTag: ⚠️ Monthly subscription product not found');
      return null;
    }
  }

  /// Start monthly subscription purchase
  /// Returns immediately, result comes through callback
  Future<void> purchaseMonthlySubscription({
    required Function(bool success, String? error) onComplete,
  }) async {
    try {
      debugPrint('$_logTag: 🛒 Starting monthly subscription purchase...');

      final product = monthlySubscription;
      if (product == null) {
        debugPrint(
          '$_logTag: ⚠️ Real products not available, falling back to mock subscription',
        );
        await _startMockSubscription(onComplete);
        return;
      }

      _onPurchaseComplete = onComplete;

      // Create purchase param
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName:
            null, // Optional: can add user ID for fraud detection
      );

      // Start the purchase flow
      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        debugPrint('$_logTag: ❌ Failed to start purchase flow');
        onComplete(false, 'Failed to start purchase process');
        _onPurchaseComplete = null;
      } else {
        debugPrint('$_logTag: ✅ Purchase flow started, waiting for result...');
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Purchase error: $e');
      onComplete(false, 'Purchase failed: $e');
      _onPurchaseComplete = null;
    }
  }

  /// Handle purchase updates from the platform
  void _onPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      debugPrint(
        '$_logTag: 📱 Purchase update: ${purchaseDetails.status} for ${purchaseDetails.productID}',
      );

      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          _handlePendingPurchase(purchaseDetails);
          break;
        case PurchaseStatus.purchased:
          _handleSuccessfulPurchase(purchaseDetails);
          break;
        case PurchaseStatus.error:
          _handlePurchaseError(purchaseDetails);
          break;
        case PurchaseStatus.canceled:
          _handlePurchaseCanceled(purchaseDetails);
          break;
        case PurchaseStatus.restored:
          _handleRestoredPurchase(purchaseDetails);
          break;
      }
    }
  }

  /// Handle pending purchase (user still in payment flow)
  void _handlePendingPurchase(PurchaseDetails purchaseDetails) {
    debugPrint('$_logTag: ⏳ Purchase pending for ${purchaseDetails.productID}');
    // Show loading state to user - purchase is still processing
  }

  /// Handle successful purchase - THE CRITICAL PART
  void _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) async {
    try {
      debugPrint(
        '$_logTag: ✅ Purchase successful for ${purchaseDetails.productID}',
      );
      debugPrint(
        '$_logTag: 🔑 Purchase token: ${purchaseDetails.verificationData.serverVerificationData}',
      );

      // CRITICAL: Verify with our backend before showing success
      Map<String, dynamic>? verificationResult;

      if (Platform.isAndroid) {
        verificationResult = await _subscriptionApi.verifyGooglePurchase(
          purchaseToken:
              purchaseDetails.verificationData.serverVerificationData,
          productId: purchaseDetails.productID,
        );
      } else if (Platform.isIOS) {
        verificationResult = await _subscriptionApi.verifyApplePurchase(
          receiptData: purchaseDetails.verificationData.serverVerificationData,
          productId: purchaseDetails.productID,
        );
      }

      if (verificationResult != null &&
          verificationResult['status'] == 'verified') {
        debugPrint('$_logTag: ✅ Backend verification successful!');
        _onPurchaseComplete?.call(true, null);
      } else {
        debugPrint('$_logTag: ❌ Backend verification failed');
        _onPurchaseComplete?.call(false, 'Purchase verification failed');
      }

      // Complete the purchase (required for both platforms)
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
        debugPrint('$_logTag: ✅ Purchase completed');
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Error handling successful purchase: $e');
      _onPurchaseComplete?.call(false, 'Verification error: $e');
    } finally {
      _onPurchaseComplete = null;
    }
  }

  /// Handle purchase error
  void _handlePurchaseError(PurchaseDetails purchaseDetails) {
    debugPrint('$_logTag: ❌ Purchase error: ${purchaseDetails.error}');

    String errorMessage = 'Purchase failed';
    if (purchaseDetails.error != null) {
      errorMessage = purchaseDetails.error!.message ?? errorMessage;
    }

    _onPurchaseComplete?.call(false, errorMessage);
    _onPurchaseComplete = null;
  }

  /// Handle purchase cancellation
  void _handlePurchaseCanceled(PurchaseDetails purchaseDetails) {
    debugPrint('$_logTag: 🚫 Purchase canceled by user');
    _onPurchaseComplete?.call(false, 'Purchase was canceled');
    _onPurchaseComplete = null;
  }

  /// Handle restored purchase (iOS)
  void _handleRestoredPurchase(PurchaseDetails purchaseDetails) {
    debugPrint('$_logTag: 🔄 Purchase restored: ${purchaseDetails.productID}');
    // Handle restored purchases similar to successful purchases
    _handleSuccessfulPurchase(purchaseDetails);
  }

  /// Check for pending purchases on startup
  Future<void> _checkPendingPurchases() async {
    try {
      debugPrint('$_logTag: 🔍 Checking for pending purchases...');

      // Note: queryPastPurchases is deprecated, but keeping for compatibility
      // In newer versions, purchases are automatically handled through purchaseStream
      debugPrint(
        '$_logTag: Pending purchases will be handled through purchase stream',
      );
    } catch (e) {
      debugPrint('$_logTag: ❌ Error checking pending purchases: $e');
    }
  }

  /// Restore purchases (iOS requirement)
  Future<bool> restorePurchases() async {
    try {
      debugPrint('$_logTag: 🔄 Restoring purchases...');

      if (Platform.isIOS) {
        await _inAppPurchase.restorePurchases();
        return true;
      } else {
        debugPrint('$_logTag: ⚠️ Restore not needed on Android');
        return true;
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Restore error: $e');
      return false;
    }
  }

  /// Dispose of the service
  void dispose() {
    debugPrint('$_logTag: 🧹 Disposing purchase service');
    _onPurchaseComplete = null;
  }

  /// Check if IAP is available
  bool get isAvailable => _isAvailable;

  /// Get available products
  List<ProductDetails> get products => _products;

  /// Get past purchases
  List<PurchaseDetails> get purchases => _purchases;

  /// Mock subscription fallback when real IAP products aren't available
  Future<void> _startMockSubscription(
    Function(bool success, String? error) onComplete,
  ) async {
    try {
      debugPrint('$_logTag: 🧪 Starting mock subscription flow...');

      // Simulate processing delay
      await Future.delayed(const Duration(seconds: 2));

      // Call appropriate mock verification endpoint based on platform
      Map<String, dynamic>? verificationResult;

      if (Platform.isIOS) {
        verificationResult = await _subscriptionApi.verifyApplePurchase(
          receiptData: 'mock_receipt_${DateTime.now().millisecondsSinceEpoch}',
          productId: 'familynest_premium_monthly',
        );
      } else {
        verificationResult = await _subscriptionApi.verifyGooglePurchase(
          purchaseToken: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
          productId: 'familynest_premium_monthly',
        );
      }

      if (verificationResult != null &&
          verificationResult['status'] == 'verified') {
        debugPrint('$_logTag: ✅ Mock subscription verification successful!');
        onComplete(true, null);
      } else {
        debugPrint('$_logTag: ❌ Mock subscription verification failed');
        onComplete(false, 'Mock verification failed');
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Error in mock subscription: $e');
      onComplete(false, 'Mock subscription error: $e');
    }
  }
}
