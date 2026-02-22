// lib/features/account/widgets/upgrade_options_dialog.dart
// ✅ UPDATED: Prevents duplicate monthly subscriptions

import 'package:flutter/material.dart';
import 'package:weldqai_app/core/services/pricing_service.dart';
import 'package:weldqai_app/core/services/payment_service.dart';
import 'package:weldqai_app/core/services/subscription_service.dart'; // ✅ ADDED

/// Helper to show the dialog
void showUpgradeOptionsDialog(BuildContext context) async {
  // ✅ Check subscription status first
  final status = await SubscriptionService().getStatus();
  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (context) => Dialog(
      child: UpgradeOptionsDialog(currentStatus: status), // ✅ Pass status
    ),
  );
}

class UpgradeOptionsDialog extends StatelessWidget {
  final SubscriptionStatus currentStatus; // ✅ ADDED
  
  const UpgradeOptionsDialog({
    super.key,
    required this.currentStatus,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ OPTION B: If user has active monthly subscription, show special view
    if (currentStatus.type == SubscriptionType.monthlyIndividual) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          maxWidth: 600,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.workspace_premium, size: 32, color: Colors.green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Subscription',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'You have unlimited access',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: 24),
              
              // Active subscription card
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Monthly Plan Active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.green[900],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      currentStatus.currentPeriodEnd != null
                          ? 'Renews ${_formatDate(currentStatus.currentPeriodEnd!)}'
                          : 'Unlimited reports',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildFeatureRow(Icons.all_inclusive, 'Unlimited reports'),
                          _buildFeatureRow(Icons.cloud_done, 'Unlimited storage'),
                          _buildFeatureRow(Icons.workspace_premium, 'All premium features'),
                          _buildFeatureRow(Icons.support_agent, 'Priority support'),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'You already have full access to all features. No additional purchases needed!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ For non-subscribers: Show normal pricing dialog
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
        maxWidth: 600,
      ),
      child: FutureBuilder<PricingData>(
        future: PricingService().getPricing(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Text('Failed to load pricing. Please try again.'),
              ),
            );
          }

          final pricing = snapshot.data!;
          final oneReport = pricing.options['one_report']!;
          final fiveReports = pricing.options['five_reports']!;
          final monthly = pricing.options['monthly']!;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium, size: 32, color: Colors.blue),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose Your Plan',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Select the plan that works best for you',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),

                  // Pay-Per-Report Section
                  _SectionHeader(
                    icon: Icons.receipt_long,
                    title: 'Pay Per Report',
                    subtitle: 'Perfect for occasional use',
                  ),
                  SizedBox(height: 12),
                  
                  Row(
                    children: [
                      // 1 Report Card
                      Expanded(
                        child: _PricingCard(
                          title: '1 Report',
                          price: oneReport.formatAmount(pricing.currencySymbol),
                          perReport: '${oneReport.formatAmount(pricing.currencySymbol)} per report',
                          features: [
                            '1 complete report',
                            'Cloud storage',
                            'PDF export',
                            'No watermark',
                          ],
                          compact: true,
                          onTap: () async {
                            final paymentService = PaymentService();
                            try {
                              await paymentService.buyReports(
                                credits: 1,
                                stripePriceId: oneReport.stripePriceId,
                              );
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Payment failed: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          buttonLabel: 'Get Started',
                        ),
                      ),
                      SizedBox(width: 12),
                      // 5 Reports Card
                      Expanded(
                        child: _PricingCard(
                          title: '5 Reports',
                          price: fiveReports.formatAmount(pricing.currencySymbol),
                          perReport: '${pricing.currencySymbol}${(fiveReports.amount / 5).toStringAsFixed(2)} each',
                          savings: fiveReports.promotionLabel ?? 'Most Popular',
                          features: [
                            '5 complete reports',
                            'Cloud storage',
                            'PDF export',
                            'No watermark',
                          ],
                          compact: true,
                          onTap: () async {
                            final paymentService = PaymentService();
                            try {
                              await paymentService.buyReports(
                                credits: 5,
                                stripePriceId: fiveReports.stripePriceId,
                              );
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Payment failed: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          buttonLabel: 'Choose Plan',
                          popular: true,
                        ),
                      ),
                    ],
                  ),

                  Divider(height: 32),

                  // Monthly Subscription Section
                  _SectionHeader(
                    icon: Icons.all_inclusive,
                    title: 'Unlimited Monthly',
                    subtitle: 'Best value for regular users',
                  ),
                  SizedBox(height: 12),
                  
                  _PricingCard(
                    title: 'Individual Plan',
                    price: '${monthly.formatAmount(pricing.currencySymbol)}/month',
                    perReport: 'Unlimited reports',
                    features: [
                      'Unlimited complete reports',
                      'Unlimited storage',
                      'No watermarks',
                      'Offline sync',
                      'Priority support',
                      'Custom templates',
                      'Advanced analytics',
                    ],
                    onTap: () async {
                      final paymentService = PaymentService();
                      try {
                        await paymentService.subscribe(
                          stripePriceId: monthly.stripePriceId,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Subscription failed: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    buttonLabel: 'Start Subscription',
                    highlighted: true,
                  ),

                  SizedBox(height: 16),

                  // Value comparison
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 20, color: Colors.blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Need 18+ reports per month? Monthly subscription saves you money!',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[700]),
        SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String title;
  final String price;
  final String perReport;
  final String? savings;
  final List<String> features;
  final VoidCallback onTap;
  final String buttonLabel;
  final bool compact;
  final bool highlighted;
  final bool popular;

  const _PricingCard({
    required this.title,
    required this.price,
    required this.perReport,
    this.savings,
    required this.features,
    required this.onTap,
    required this.buttonLabel,
    this.compact = false,
    this.highlighted = false,
    this.popular = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: highlighted
              ? Colors.blue
              : popular
                  ? Colors.orange
                  : Colors.grey.shade300,
          width: highlighted || popular ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: highlighted
            ? Colors.blue.withValues(alpha: 0.05)
            : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (savings != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: popular ? Colors.orange : Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    savings!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            price,
            style: TextStyle(
              fontSize: compact ? 18 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          SizedBox(height: 4),
          Text(
            perReport,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
          if (!compact) ...[
            SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 16, color: Colors.green),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        f,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: highlighted ? Colors.blue : null,
                foregroundColor: highlighted ? Colors.white : null,
              ),
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

// ✅ NEW: Shows green card for already subscribed users

// ✅ Helper for building feature rows in subscription status
Widget _buildFeatureRow(IconData icon, String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.green),
        SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(fontSize: 14),
        ),
      ],
    ),
  );
}

// ✅ NEW: Formats dates nicely
String _formatDate(DateTime date) {
  final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}