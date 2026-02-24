// lib/core/providers/connectivity_provider.dart
//
// Real-time connectivity stream via connectivity_plus.
// Emits true = online (any non-none result), false = offline.
// Seeds with an immediate checkConnectivity() call so the first
// widget read never sees AsyncLoading for more than one frame.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the device has any active network connection.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  // Emit initial state immediately so UI doesn't flash loading.
  final initial = await connectivity.checkConnectivity();
  yield initial.any((r) => r != ConnectivityResult.none);

  // Stream subsequent changes.
  yield* connectivity.onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));
});
