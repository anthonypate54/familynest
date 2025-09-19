import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/subscription.dart';
import '../utils/platform_text_helper.dart';

class SubscriptionCard extends StatelessWidget {
  final Subscription? subscription;
  final VoidCallback? onUpgrade;
  final VoidCallback? onManagePayment;
  final VoidCallback? onViewBilling;
  final VoidCallback? onCancel;

  const SubscriptionCard({
    Key? key,
    this.subscription,
    this.onUpgrade,
    this.onManagePayment,
    this.onViewBilling,
    this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (subscription == null) {
      return _buildNoSubscriptionCard(context);
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              subscription!.statusColor.withValues(alpha: 0.1),
              subscription!.statusColor.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildSubscriptionInfo(),
              const SizedBox(height: 16),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoSubscriptionCard(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.withValues(alpha: 0.1),
              Colors.blue.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.star_border, color: Colors.blue, size: 32),
                  SizedBox(width: 12),
                  Text(
                    'Start Your Free Trial',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Get 30 days free, then \$${subscription?.monthlyPrice?.toStringAsFixed(2) ?? '2.99'}/month',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                '• Share memories with family\n• Unlimited photo storage\n• Video messages\n• No ads',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.store, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Visit App Store or Google Play to start your free trial',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: subscription!.statusColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            subscription!.statusDisplayText,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const Spacer(),
        if (subscription!.isInTrial)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              subscription!.trialTimeRemainingText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        if (subscription!.isCancelledWithAccess)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _getCancelledAccessText(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSubscriptionInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FamilyNest Premium',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subscription!.priceDisplayText,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 12),
        if (subscription!.isInTrial) ...[
          _buildInfoRow(
            icon: Icons.schedule,
            label: 'Trial ends',
            value:
                subscription!.trialEndDate != null
                    ? '${subscription!.trialEndDate!.month}/${subscription!.trialEndDate!.day}/${subscription!.trialEndDate!.year}'
                    : 'Unknown',
          ),
          const SizedBox(height: 8),
        ],
        if (subscription!.isActive &&
            subscription!.subscriptionEndDate != null) ...[
          _buildInfoRow(
            icon: Icons.payment,
            label: 'Next billing',
            value:
                '${subscription!.subscriptionEndDate!.month}/${subscription!.subscriptionEndDate!.day}/${subscription!.subscriptionEndDate!.year}',
          ),
          const SizedBox(height: 8),
        ],
        _buildInfoRow(
          icon: Icons.credit_card,
          label: 'Payment method',
          value: subscription!.paymentMethodDisplayText,
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  String _getCancelledAccessText() {
    if (!subscription!.isCancelledWithAccess ||
        subscription!.subscriptionEndDate == null) {
      return 'Access expired';
    }

    final now = DateTime.now();
    final endDate = subscription!.subscriptionEndDate!;
    final daysLeft = endDate.difference(now).inDays;

    if (daysLeft > 0) {
      return 'Access until ${daysLeft == 1 ? '1 day' : '$daysLeft days'}';
    } else {
      return 'Access ends today';
    }
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        // Billing statement info box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  PlatformTextHelper.getSubscriptionInfoText(),
                  style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // For trial users, show "Upgrade to Premium" button
            if (subscription!.isInTrial)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onUpgrade?.call(); // Trigger the mock subscription flow
                  },
                  icon: const Icon(Icons.upgrade, color: Colors.white),
                  label: const Text(
                    'Upgrade to Premium',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            // For active users, show unsubscribe button
            else if (subscription!.isActive)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onCancel?.call(); // Trigger unsubscribe flow
                  },
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  label: const Text(
                    'Unsubscribe',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            // For cancelled/expired users, show "Subscribe Again" button
            else if (subscription!.isCancelled || subscription!.isExpired)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onUpgrade?.call(); // Trigger subscribe again flow
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'Subscribe Again',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            // Always show spacer and History button if there's a subscription action button
            if (subscription!.isActive ||
                subscription!.isInTrial ||
                subscription!.isCancelled ||
                subscription!.isExpired)
              const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onViewBilling?.call();
                },
                icon: const Icon(Icons.receipt_long),
                label: const Text('History'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
