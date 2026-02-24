// lib/core/providers/workspace_provider.dart
//
// Manages which workspace (own vs. shared collaborator) is currently active.
// Subscription status is no longer stored here — use subscriptionStatusProvider
// from lib/core/providers/subscription_providers.dart instead.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class WorkspaceProvider extends ChangeNotifier {
  String? _activeWorkspaceUid;
  String? _activeWorkspaceOwnerEmail;

  /// Get the currently active workspace UID.
  /// Returns the current user's own UID when no shared workspace is active.
  /// Returns an empty string during auth transitions so Firestore queries
  /// fail gracefully rather than crashing.
  String get activeWorkspace {
    return _activeWorkspaceUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  /// True when the user is viewing their own workspace (not a collaborator's).
  bool get isViewingOwnWorkspace {
    return _activeWorkspaceUid == null ||
        _activeWorkspaceUid == FirebaseAuth.instance.currentUser?.uid;
  }

  /// Display email of the workspace owner when viewing a shared workspace.
  String? get activeWorkspaceOwnerEmail => _activeWorkspaceOwnerEmail;

  /// Switch to another user's workspace (collaboration feature).
  void switchToWorkspace(String ownerUid, {String? ownerEmail}) {
    _activeWorkspaceUid = ownerUid;
    _activeWorkspaceOwnerEmail = ownerEmail;
    notifyListeners();
  }

  /// Return to the current user's own workspace.
  void switchToMyWorkspace() {
    _activeWorkspaceUid = null;
    _activeWorkspaceOwnerEmail = null;
    notifyListeners();
  }

  /// Reset on sign-out.
  void reset() {
    _activeWorkspaceUid = null;
    _activeWorkspaceOwnerEmail = null;
    notifyListeners();
  }
}
