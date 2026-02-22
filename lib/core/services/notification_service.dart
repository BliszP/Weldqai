// lib/core/services/notification_service.dart
// ✅ Complete FCM notification service for web

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _currentToken;
  String? _userId;

  /// Initialize notifications for a user
  /// Call this after user signs in
  Future<void> initialize(String userId) async {
    if (!kIsWeb) {
      AppLogger.warning('⚠️ NotificationService: Web-only service called on non-web platform');
      return;
    }

    _userId = userId;
    AppLogger.debug('🔔 NotificationService: Initializing for user $userId');

    try {
      // Request permission
      final permission = await _requestPermission();
      if (!permission) {
        AppLogger.warning('⚠️ NotificationService: Permission denied');
        return;
      }

      // Get token
      await _getAndSaveToken();

      // Handle token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        AppLogger.debug('🔄 NotificationService: Token refreshed');
        _currentToken = newToken;
        _saveTokenToFirestore(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        AppLogger.debug('📨 NotificationService: Foreground message received');
        AppLogger.debug('  Title: ${message.notification?.title}');
        AppLogger.debug('  Body: ${message.notification?.body}');
        
        // Note: Web automatically shows notifications via service worker
        // This listener is for custom handling if needed
      });

      AppLogger.info('✅ NotificationService: Initialized successfully');
    } catch (e) {
      AppLogger.error('❌ NotificationService: Initialization failed: $e');
    }
  }

  /// Request notification permission
  Future<bool> _requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      final granted = settings.authorizationStatus == AuthorizationStatus.authorized;
      AppLogger.debug('🔔 NotificationService: Permission ${granted ? "granted" : "denied"}');
      
      return granted;
    } catch (e) {
      AppLogger.error('❌ NotificationService: Permission request failed: $e');
      return false;
    }
  }

  /// Get FCM token and save to Firestore
  Future<void> _getAndSaveToken() async {
    try {
      // Get VAPID key from your Firebase project settings
      // Web app → Cloud Messaging → Web configuration → Key pair
      final token = await _messaging.getToken(
        vapidKey: 'BB6yYyBYJ2vUf_U4pWmLiCJUdQSH-sxoeGBRAjQt0LMUIM3Kj3COC6_axg7D8MCM7L1DGeeLItv0AcNEo1nhkCs', // ⚠️ REPLACE THIS!
      );

      if (token != null) {
        _currentToken = token;
        AppLogger.debug('🔑 NotificationService: Token obtained');
        await _saveTokenToFirestore(token);
      } else {
        AppLogger.warning('⚠️ NotificationService: No token obtained');
      }
    } catch (e) {
      AppLogger.error('❌ NotificationService: Token retrieval failed: $e');
    }
  }

  /// Save token to Firestore
  Future<void> _saveTokenToFirestore(String token) async {
    if (_userId == null) {
      AppLogger.warning('⚠️ NotificationService: Cannot save token - no userId');
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('profile')
          .doc('info');

      await docRef.set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      AppLogger.info('✅ NotificationService: Token saved to Firestore');
    } catch (e) {
      AppLogger.error('❌ NotificationService: Failed to save token: $e');
    }
  }

  /// Remove token from Firestore (call on sign out)
  Future<void> removeToken() async {
    if (_userId == null || _currentToken == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('profile')
          .doc('info');

      await docRef.update({
        'fcmTokens': FieldValue.arrayRemove([_currentToken]),
      });

      await _messaging.deleteToken();
      
      _currentToken = null;
      _userId = null;

      AppLogger.info('✅ NotificationService: Token removed');
    } catch (e) {
      AppLogger.error('❌ NotificationService: Failed to remove token: $e');
    }
  }

  /// Check current permission status
  Future<bool> hasPermission() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// Get current token (for debugging)
  String? get currentToken => _currentToken;

  /// Request permission again (for settings screen)
  Future<bool> requestPermissionAgain() async {
    return await _requestPermission();
  }
}