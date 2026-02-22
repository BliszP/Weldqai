// lib/core/services/pricing_service.dart
// ✅ Updated: Only 3 pricing tiers - $3, $14, $50 monthly
// Removed 10 reports option

import 'package:cloud_firestore/cloud_firestore.dart';

class PricingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Get current pricing for user's region
  Future<PricingData> getPricing({String region = 'default'}) async {
    try {
      // Fetch pricing from Firestore
      final doc = await _db
          .collection('pricing')
          .doc(region) // 'default', 'nigeria', 'ghana', etc.
          .get();

      if (!doc.exists) {
        // Fallback to default pricing
        final defaultDoc = await _db.collection('pricing').doc('default').get();
        if (!defaultDoc.exists) {
          throw Exception('No pricing configuration found');
        }
        return PricingData.fromFirestore(defaultDoc.data()!);
      }

      return PricingData.fromFirestore(doc.data()!);
    } catch (e) {
      // Fallback to hardcoded prices if Firestore fails
      return PricingData.fallback();
    }
  }

  /// Get pricing based on user's location (detected from IP or profile)
  Future<PricingData> getPricingForUser(String userId) async {
    // TODO: Detect user's country from profile or IP
    // For now, return default
    return getPricing();
  }
}

/// Pricing data structure
class PricingData {
  final String currency;
  final String currencySymbol;
  final Map<String, PriceOption> options;
  final String region;

  PricingData({
    required this.currency,
    required this.currencySymbol,
    required this.options,
    required this.region,
  });

  factory PricingData.fromFirestore(Map<String, dynamic> data) {
    return PricingData(
      currency: data['currency'] ?? 'USD',
      currencySymbol: data['currencySymbol'] ?? '\$',
      region: data['region'] ?? 'default',
      options: {
        'one_report': PriceOption.fromMap(data['one_report'] ?? {}),
        'five_reports': PriceOption.fromMap(data['five_reports'] ?? {}),
        'monthly': PriceOption.fromMap(data['monthly'] ?? {}),
      },
    );
  }

  /// Fallback prices if Firestore is unavailable
  /// Updated: Only 3 tiers - $3, $14, $50/month
  factory PricingData.fallback() {
    return PricingData(
      currency: 'USD',
      currencySymbol: '\$',
      region: 'default',
      options: {
        'one_report': PriceOption(
          amount: 3.00,
          stripePriceId: 'price_1Sb9c7Cfx756A1WKgYbqLXMU',
          credits: 1,
        ),
        'five_reports': PriceOption(
          amount: 14.00,
          stripePriceId: 'price_1Sb9ceCfx756A1WKdQed1rHE',
          credits: 5,
          promotionLabel: 'Most Popular',
        ),
        'monthly': PriceOption(
          amount: 50.00,
          stripePriceId: 'price_1Sb9dTCfx756A1WKzbGaQli4',
          isRecurring: true,
        ),
      },
    );
  }
}

/// Individual price option
class PriceOption {
  final double amount;
  final String stripePriceId; // Stripe Price ID for checkout
  final int? credits; // For pay-per-report
  final bool isRecurring; // true for monthly subscription
  final String? promotionLabel; // "Most Popular", "Best Value", etc.

  PriceOption({
    required this.amount,
    required this.stripePriceId,
    this.credits,
    this.isRecurring = false,
    this.promotionLabel,
  });

  factory PriceOption.fromMap(Map<String, dynamic> data) {
    return PriceOption(
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      stripePriceId: data['stripePriceId'] ?? '',
      credits: data['credits'] as int?,
      isRecurring: data['isRecurring'] == true,
      promotionLabel: data['promotionLabel'] as String?,
    );
  }

  /// Format amount with currency symbol
  String formatAmount(String currencySymbol) {
    return '$currencySymbol${amount.toStringAsFixed(2)}';
  }

  /// Calculate per-report cost for bundles
  double get perReportCost {
    if (credits == null || credits == 0) return amount;
    return amount / credits!;
  }

  /// Calculate savings percentage compared to single report price
  String calculateSavings(double singleReportPrice) {
    if (credits == null || credits! <= 1) return '';
    
    final totalAtSinglePrice = singleReportPrice * credits!;
    final savings = ((totalAtSinglePrice - amount) / totalAtSinglePrice * 100);
    
    if (savings <= 0) return '';
    return 'Save ${savings.toStringAsFixed(0)}%';
  }
}