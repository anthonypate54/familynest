import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' as io;
import '../services/api_service.dart';
import '../services/subscription_api_service.dart';
import '../services/purchase_service.dart';
import '../utils/platform_text_helper.dart';
import '../widgets/gradient_background.dart';
import '../models/subscription.dart';
import 'login_screen.dart';
import '../main.dart'; // For MainAppContainer

class SubscriptionRequiredScreen extends StatefulWidget {
  final String username;
  final Subscription? subscription;

  const SubscriptionRequiredScreen({
    Key? key,
    required this.username,
    this.subscription,
  }) : super(key: key);

  @override
  State<SubscriptionRequiredScreen> createState() =>
      _SubscriptionRequiredScreenState();
}

class _SubscriptionRequiredScreenState
    extends State<SubscriptionRequiredScreen> {
  PurchaseService? _purchaseService;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePurchaseService();
  }

  Future<void> _initializePurchaseService() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final subscriptionApi = SubscriptionApiService(apiService);

      _purchaseService = PurchaseService(subscriptionApi);
      final success = await _purchaseService!.initialize();

      setState(() {
        _isInitialized = success;
        if (!success) {
          _errorMessage = 'Unable to connect to store';
        }
      });
    } catch (e) {
      setState(() {
        _isInitialized = false;
        _errorMessage = 'Store initialization failed: $e';
      });
    }
  }

  @override
  void dispose() {
    _purchaseService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header
                const Icon(Icons.lock_outline, size: 80, color: Colors.white),
                const SizedBox(height: 20),
                Text(
                  widget.subscription?.trialExpired == true
                      ? 'Your Free Trial Has Expired'
                      : 'Subscription Required',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Subscribe to continue using FamilyNest',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Pricing Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'FamilyNest Premium',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '\$${widget.subscription?.monthlyPrice.toStringAsFixed(2) ?? '2.99'}',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          Text(
                            '/month',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Features
                      ..._buildFeatures(),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Subscribe Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        _isInitialized && !_isLoading
                            ? _startSubscription
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : Text(
                              _isInitialized
                                  ? PlatformTextHelper.getSubscribeButtonText()
                                  : 'Store Unavailable',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                  ),
                ),
                const SizedBox(height: 15),

                // Logout Button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => _logout(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.8),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 16,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFeatures() {
    final features = [
      'Unlimited photo and video storage',
      'HD video messages',
      'Multiple family groups',
      'Ad-free experience',
      'Priority support',
    ];

    return features
        .map(
          (feature) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    feature,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  /// Start the real subscription purchase flow
  Future<void> _startSubscription() async {
    if (_purchaseService == null || !_isInitialized) {
      _showError('Store not available. Please try again later.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _purchaseService!.purchaseMonthlySubscription(
        onComplete: (bool success, String? error) {
          setState(() {
            _isLoading = false;
          });

          if (success) {
            _handleSubscriptionSuccess();
          } else {
            _showError(error ?? 'Purchase failed');
          }
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('Purchase error: $e');
    }
  }

  /// Handle successful subscription - navigate to subscription tab
  void _handleSubscriptionSuccess() {
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 Welcome to FamilyNest Premium!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );

    // Navigate to main app with subscription tab after short delay
    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted) {
        try {
          // Get current user data to get userId and userRole
          final apiService = Provider.of<ApiService>(context, listen: false);
          final userResponse = await apiService.getCurrentUser();

          if (userResponse != null && mounted) {
            final userId = userResponse['userId'];
            final userRole = userResponse['role'] ?? 'USER';

            // Navigate to MainAppContainer with Profile tab selected (subscription sub-tab)
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder:
                    (context) => MainAppContainer(
                      userId: userId,
                      userRole: userRole,
                      initialTabIndex: 2, // Profile tab
                      initialProfileSubTab: 1, // Subscription sub-tab
                    ),
              ),
              (route) => false, // Remove all previous routes
            );
          }
        } catch (e) {
          debugPrint('Error getting user data for navigation: $e');
          // Fallback: just pop back
          Navigator.of(context).pop();
        }
      }
    });
  }

  /// Show error dialog
  void _showError(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Subscription Error'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Details: $_errorMessage',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
              if (!_isInitialized)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _initializePurchaseService();
                  },
                  child: const Text('Retry'),
                ),
            ],
          ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  // Logout logic
                  final apiService = Provider.of<ApiService>(
                    context,
                    listen: false,
                  );
                  await apiService.logout();

                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Logout'),
              ),
            ],
          ),
    );
  }
}
