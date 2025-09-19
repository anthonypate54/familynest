import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../widgets/subscription_card.dart';
import '../services/api_service.dart';
import '../services/subscription_api_service.dart';
import '../services/purchase_service.dart';
import '../utils/platform_text_helper.dart';
import 'dart:io' as io;

class SubscriptionTab extends StatefulWidget {
  final User user;
  final VoidCallback onUserDataRefresh;

  const SubscriptionTab({
    Key? key,
    required this.user,
    required this.onUserDataRefresh,
  }) : super(key: key);

  @override
  State<SubscriptionTab> createState() => _SubscriptionTabState();
}

class _SubscriptionTabState extends State<SubscriptionTab> {
  void _showManageSubscriptionDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Manage Subscription'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  io.Platform.isIOS
                      ? 'Your subscription is managed through the App Store.'
                      : 'Your subscription is managed through Google Play.',
                ),
                const SizedBox(height: 16),
                Text(
                  io.Platform.isIOS
                      ? 'To manage your subscription:\n• Open Settings on your device\n• Tap your name at the top\n• Tap Subscriptions\n• Select FamilyNest'
                      : 'To manage your subscription:\n• Open Google Play Store\n• Tap Menu (☰)\n• Tap Subscriptions\n• Select FamilyNest',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  /// Start subscription purchase flow from profile tab
  void _startSubscriptionUpgrade() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final subscriptionApi = SubscriptionApiService(apiService);

      // Import the real purchase service
      final purchaseService = PurchaseService(subscriptionApi);

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing store...'),
                ],
              ),
            ),
      );

      // Initialize purchase service
      final initialized = await purchaseService.initialize();

      // Close loading dialog
      if (context.mounted) Navigator.of(context).pop();

      if (!initialized) {
        _showError('Store not available. Please try again later.');
        return;
      }

      // Start purchase flow
      await purchaseService.purchaseMonthlySubscription(
        onComplete: (bool success, String? error) {
          if (success) {
            _showSuccess();
            widget.onUserDataRefresh(); // Refresh user data
          } else {
            _showError(error ?? 'Purchase failed');
          }
        },
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      _showError('Purchase error: $e');
    }
  }

  void _showSuccess() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('🎉 Success!'),
            content: const Text(
              'Welcome to FamilyNest Premium! Your subscription is now active.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Awesome!'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Subscription Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  /// Mock subscription flow for testing before Google Play Console setup
  void _startMockSubscription() async {
    // Show mock Google Play dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  io.Platform.isIOS ? Icons.apple : Icons.shop,
                  color: io.Platform.isIOS ? Colors.black : Colors.green,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(PlatformTextHelper.getStoreName()),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FamilyNest Premium',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '\$2.99/month',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '• Unlimited photo storage\n• HD video messages\n• Multiple families\n• Ad-free experience',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '🧪 MOCK PURCHASE - No real payment',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => _processMockPurchase(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  'Subscribe',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  /// Process the mock purchase (simulates Google Play → Backend flow)
  void _processMockPurchase() async {
    // Close the purchase dialog
    Navigator.of(context).pop();

    // Show processing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing purchase...'),
              ],
            ),
          ),
    );

    try {
      // Simulate Google Play response delay
      await Future.delayed(const Duration(seconds: 2));

      // Call our backend's mock Google verification
      final apiService = Provider.of<ApiService>(context, listen: false);
      final subscriptionApi = SubscriptionApiService(apiService);

      final result =
          io.Platform.isIOS
              ? await subscriptionApi.verifyApplePurchase(
                receiptData:
                    'mock_receipt_${DateTime.now().millisecondsSinceEpoch}',
                productId: 'familynest_premium_monthly',
              )
              : await subscriptionApi.verifyGooglePurchase(
                purchaseToken:
                    'mock_token_${DateTime.now().millisecondsSinceEpoch}',
                productId: 'familynest_premium_monthly',
              );

      // Close processing dialog
      if (context.mounted) Navigator.of(context).pop();

      if (result != null && result['status'] == 'verified') {
        debugPrint('🎉 Mock purchase successful! Result: $result');
        _showSuccess();

        // Add delay before refresh to ensure backend update completed
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint('🔄 Triggering user data refresh...');
        widget.onUserDataRefresh(); // Refresh subscription status
      } else {
        debugPrint('❌ Mock purchase failed. Result: $result');
        _showError('Mock purchase verification failed');
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      _showError('Mock purchase error: $e');
    }
  }

  Future<void> _showBillingDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            title: Text('Loading Payment History'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Fetching your payment history...'),
              ],
            ),
          ),
    );

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final subscriptionApi = SubscriptionApiService(apiService);
      final historyData = await subscriptionApi.getPaymentHistory();

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      if (historyData != null && historyData['transactions'] != null) {
        final transactions = historyData['transactions'] as List;

        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Payment History'),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child:
                      transactions.isEmpty
                          ? const Center(
                            child: Text('No payment history available'),
                          )
                          : ListView.builder(
                            itemCount: transactions.length,
                            itemBuilder: (context, index) {
                              final transaction = transactions[index];
                              return ListTile(
                                leading: Icon(
                                  _getTransactionIcon(transaction['status']),
                                  color: _getTransactionColor(
                                    transaction['status'],
                                  ),
                                ),
                                title: Text(
                                  _formatTransactionTitle(transaction),
                                ),
                                subtitle: Text(
                                  'Amount: \$${transaction['amount']}\n'
                                  'Date: ${_formatTransactionDate(transaction['created_at'])}\n'
                                  'Platform: ${PlatformTextHelper.formatTransactionPlatform(transaction['platform'])}',
                                ),
                                isThreeLine: true,
                              );
                            },
                          ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
        );
      } else {
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Payment History'),
                content: const Text(
                  'No payment history available at this time.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Error'),
              content: Text('Failed to load payment history: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    }
  }

  Future<void> _showCancelSubscriptionDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel Subscription'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Are you sure you want to cancel your subscription?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'You will lose access to premium features at the end of your current billing period.',
                ),
                const SizedBox(height: 16),
                Text(
                  io.Platform.isIOS
                      ? 'Note: This will only cancel in our system. You must also cancel through the App Store to stop billing.'
                      : 'Note: This will only cancel in our system. You must also cancel through Google Play to stop billing.',
                  style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep Subscription'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Cancel Subscription'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final subscriptionApi = SubscriptionApiService(apiService);
        final success = await subscriptionApi.cancelSubscription();

        if (!mounted) return;

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Subscription cancelled successfully'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onUserDataRefresh(); // Refresh user data
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to cancel subscription'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling subscription: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Get appropriate icon for transaction status
  IconData _getTransactionIcon(String? status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      case 'failed':
        return Icons.error;
      case 'pending':
        return Icons.pending;
      default:
        return Icons.help_outline;
    }
  }

  /// Get appropriate color for transaction status
  Color _getTransactionColor(String? status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'failed':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// Format transaction title for display
  String _formatTransactionTitle(Map<String, dynamic> transaction) {
    final description = transaction['description'] as String?;
    final productId = transaction['product_id'] as String?;

    // Clean up product ID to readable format
    if (productId != null) {
      switch (productId) {
        case 'familynest_premium_monthly':
          return 'FamilyNest Premium (Monthly)';
        case 'familynest_premium_yearly':
          return 'FamilyNest Premium (Yearly)';
        case 'familynest_premium_weekly':
          return 'FamilyNest Premium (Weekly)';
        default:
          // Convert snake_case to Title Case
          return productId
              .split('_')
              .map(
                (word) =>
                    word.isNotEmpty
                        ? word[0].toUpperCase() +
                            word.substring(1).toLowerCase()
                        : word,
              )
              .join(' ');
      }
    }

    // Fallback to description or default
    if (description != null && description.isNotEmpty) {
      // Clean up description if it contains the raw product ID
      if (description.contains('familynest_premium_monthly')) {
        return description.replaceAll(
          'familynest_premium_monthly',
          'FamilyNest Premium (Monthly)',
        );
      }
      return description;
    }

    return 'Subscription Payment';
  }

  /// Format transaction date for display
  String _formatTransactionDate(dynamic dateValue) {
    try {
      if (dateValue == null) return 'Unknown';

      DateTime date;
      if (dateValue is String) {
        // Try parsing as ISO string first
        date = DateTime.parse(dateValue);
      } else if (dateValue is int) {
        // Handle milliseconds timestamp
        date = DateTime.fromMillisecondsSinceEpoch(dateValue);
      } else {
        return dateValue.toString();
      }

      // Format as readable date and time (always show actual date)
      return '${date.month}/${date.day}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      // Fallback to raw value if parsing fails
      return dateValue?.toString() ?? 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          SubscriptionCard(
            subscription: widget.user.subscription,
            onUpgrade: _startMockSubscription,
            onManagePayment: _showManageSubscriptionDialog,
            onViewBilling: _showBillingDialog,
            onCancel: _showCancelSubscriptionDialog,
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Features',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.cloud_upload,
                    title: 'Unlimited Storage',
                    description: 'Store unlimited photos and videos',
                  ),
                  _buildFeatureItem(
                    icon: Icons.video_call,
                    title: 'HD Video Messages',
                    description: 'Send high-quality video messages',
                  ),
                  _buildFeatureItem(
                    icon: Icons.group,
                    title: 'Multiple Families',
                    description: 'Join and manage multiple family groups',
                  ),
                  _buildFeatureItem(
                    icon: Icons.block,
                    title: 'Ad-Free Experience',
                    description: 'Enjoy the app without advertisements',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
