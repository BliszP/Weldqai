// lib/core/providers/subscription_providers.dart
//
// Single source of truth for subscription status.
// Both screens that previously created their own SubscriptionService()
// instances now share this one stream, halving Firestore listener count.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weldqai_app/core/services/subscription_service.dart';

/// Shared SubscriptionService instance.
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

/// Real-time subscription status stream.
/// Automatically initialised on first watch; cancelled when no longer watched.
/// Use with ref.watch(subscriptionStatusProvider) in ConsumerWidget/ConsumerState.
final subscriptionStatusProvider = StreamProvider<SubscriptionStatus>((ref) {
  final service = ref.watch(subscriptionServiceProvider);
  return service.watchStatus();
});
