import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:weldqai_app/core/services/subscription_service.dart';

class WorkspaceProvider extends ChangeNotifier {
  String? _activeWorkspaceUid;
  String? _activeWorkspaceOwnerEmail;

  final SubscriptionService _subscriptionService;
  StreamSubscription<SubscriptionStatus>? _statusSub;
  SubscriptionStatus? _subscriptionStatus;

  WorkspaceProvider({SubscriptionService? subscriptionService})
      : _subscriptionService = subscriptionService ?? SubscriptionService();

  /// Get the currently active workspace UID.
  /// Returns the current user's own UID when no shared workspace is active.
  /// Returns an empty string during auth transitions (sign-out / token refresh)
  /// so that downstream Firestore queries fail gracefully rather than crashing.
  String get activeWorkspace {
    return _activeWorkspaceUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  /// Check if viewing own workspace
  bool get isViewingOwnWorkspace {
    return _activeWorkspaceUid == null ||
        _activeWorkspaceUid == FirebaseAuth.instance.currentUser?.uid;
  }

  /// Get owner email of active workspace (for display)
  String? get activeWorkspaceOwnerEmail => _activeWorkspaceOwnerEmail;

  /// Cached subscription status. Null until the first stream event arrives.
  /// Falls back to the cached value when offline.
  SubscriptionStatus? get subscriptionStatus => _subscriptionStatus;

  /// Switch to another user's workspace
  void switchToWorkspace(String ownerUid, {String? ownerEmail}) {
    _activeWorkspaceUid = ownerUid;
    _activeWorkspaceOwnerEmail = ownerEmail;
    notifyListeners();
  }

  /// Switch back to own workspace
  void switchToMyWorkspace() {
    _activeWorkspaceUid = null;
    _activeWorkspaceOwnerEmail = null;
    notifyListeners();
  }

  /// Start listening to the subscription status stream.
  /// Call this after the user signs in. Safe to call multiple times —
  /// cancels any existing subscription before starting a new one.
  void startListening() {
    _statusSub?.cancel();
    _statusSub = _subscriptionService.watchStatus().listen((status) {
      _subscriptionStatus = status;
      notifyListeners();
    });
  }

  /// Reset on sign out — cancels stream and clears cached status.
  void reset() {
    _activeWorkspaceUid = null;
    _activeWorkspaceOwnerEmail = null;
    _statusSub?.cancel();
    _statusSub = null;
    _subscriptionStatus = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}
