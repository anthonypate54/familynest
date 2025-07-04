import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/subscription.dart';

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
              subscription!.statusColor.withOpacity(0.1),
              subscription!.statusColor.withOpacity(0.05),
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
              Colors.blue.withOpacity(0.1),
              Colors.blue.withOpacity(0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.star_border, color: Colors.blue, size: 32),
                  const SizedBox(width: 12),
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
                'Get 30 days free, then \$4.99/month',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                '• Share memories with family\n• Unlimited photo storage\n• Video messages\n• No ads',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onUpgrade,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Start Free Trial',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
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
              '${subscription!.daysLeftInTrial} days left',
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
        if (subscription!.nextBillingDate != null) ...[
          _buildInfoRow(
            icon: Icons.payment,
            label: 'Next billing',
            value:
                '${subscription!.nextBillingDate!.month}/${subscription!.nextBillingDate!.day}/${subscription!.nextBillingDate!.year}',
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

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        if (subscription!.isInTrial && !subscription!.hasPaymentMethod) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onUpgrade?.call();
              },
              icon: const Icon(Icons.upgrade),
              label: const Text('Add Payment Method'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (subscription!.hasPaymentMethod)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onManagePayment?.call();
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Payment'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (subscription!.hasPaymentMethod) const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onViewBilling?.call();
                },
                icon: const Icon(Icons.receipt),
                label: const Text('Billing'),
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
        if (subscription!.isActive || subscription!.isInTrial) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onCancel?.call();
              },
              child: Text(
                subscription!.isInTrial
                    ? 'Cancel Trial'
                    : 'Cancel Subscription',
                style: TextStyle(
                  color: Colors.red[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
