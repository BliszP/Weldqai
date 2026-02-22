// lib/core/services/payment_service.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:weldqai_app/core/services/logger_service.dart';
import 'package:weldqai_app/core/services/error_service.dart';

class PaymentService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Buy reports (pay-per-report)
  Future<void> buyReports({
    required int credits,
    required String stripePriceId,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('createCheckoutSession')
          .call({
        'priceId': stripePriceId,
        'credits': credits,
      });

      final checkoutUrl = result.data['url'] as String;

      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not open payment page');
      }
    } catch (e, st) {
      AppLogger.error('❌ buyReports failed', error: e, stackTrace: st);
      await ErrorService.captureException(e, stackTrace: st, context: 'PaymentService.buyReports');
      throw Exception('Payment failed: $e');
    }
  }

  /// Subscribe to monthly plan
  Future<void> subscribe({
    required String stripePriceId,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('createSubscription')
          .call({
        'priceId': stripePriceId,
      });

      final checkoutUrl = result.data['url'] as String;

      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not open payment page');
      }
    } catch (e, st) {
      AppLogger.error('❌ subscribe failed', error: e, stackTrace: st);
      await ErrorService.captureException(e, stackTrace: st, context: 'PaymentService.subscribe');
      throw Exception('Subscription failed: $e');
    }
  }
}
