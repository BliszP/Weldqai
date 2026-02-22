

// ignore_for_file: unused_element

// lib/core/services/push_service.dart


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

/// ---------------------------------------------------------------------------
/// Public API
/// ---------------------------------------------------------------------------
/// Call once right after sign-in:
///   await initPush(uid);
///
/// Notes:
/// - Web: make sure you have /web/firebase-messaging-sw.js with your Firebase web config,
///   and pass your Public VAPID key below.
/// - Android: ensure you have an app icon named @mipmap/ic_launcher.
/// - iOS: add push capabilities + upload APNs key in Firebase console.
/// ---------------------------------------------------------------------------

final _db   = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;
final _fln  = FlutterLocalNotificationsPlugin();

/// Replace with your **Public VAPID key** from
/// Firebase Console → Project Settings → Cloud Messaging → Web configuration
const String kWebVapidKey = 'BB6yYyBYJ2vUf_U4pWmLiCJUdQSH-sxoeGBRAjQt0LMUIM3Kj3COC6_axg7D8MCM7L1DGeeLItv0AcNEo1nhkCs';

/// Android notification channel used for foreground local notifications.
const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'weldqai_default',               // id
  'WeldQAi Alerts',                // name
  description: 'General notifications',
  importance: Importance.high,
);

/// Initialize push messaging & local notifications.
Future<void> initPush(String uid) async {
  // 1) Ask for notification permissions (required on iOS, Android 13+).
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(alert: true, badge: true, sound: true);

  // iOS: show heads-up when app is in foreground too.
  await fcm.setForegroundNotificationPresentationOptions(
    alert: true, badge: true, sound: true,
  );

  // 2) Create Android notification channel (no-op on iOS/Web).
  await _fln
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_androidChannel);

  // 3) Initialize Flutter Local Notifications (foreground display).
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _fln.initialize(
    initSettings,
    // Optional: handle taps on local notifications
    onDidReceiveNotificationResponse: (NotificationResponse resp) {
      // You can route based on resp.payload if you wish.
      // Example payload is set to msg.data.toString() below.
      AppLogger.debug('Notification tapped: ${resp.payload}');
    },
  );

  // 4) Fetch and save the FCM token. (Use VAPID key on web.)
  final token = kIsWeb
      ? await fcm.getToken(vapidKey: kWebVapidKey)
      : await fcm.getToken();

  if (token != null) {
    await _saveToken(uid, token);
  }

  // Keep token fresh (rotation, app reinstall, etc.)
  FirebaseMessaging.instance.onTokenRefresh.listen((t) => _saveToken(uid, t));

  // 5) Foreground messages → show a local notification.
  FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
    final n = msg.notification;
    // If your function sends only data messages, n can be null — fallback to data.
    final title = n?.title ?? msg.data['title'] ?? 'WeldQAi';
    final body  = n?.body  ?? msg.data['body']  ?? 'You have a new message';

    await _fln.show(
      // Unique id per notification (use hashCode to keep it simple).
      msg.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      // Give yourself a way to deep-link later
      payload: msg.data.isNotEmpty ? msg.data.toString() : null,
    );
  });

  // 6) (Optional) subscribe the user to a per-user topic.
  // You can target "user_$uid" in Cloud Functions if you prefer topics
  // (tokens array multicast is also fine).
  if (!kIsWeb) {
  await fcm.subscribeToTopic('user_$uid');
}
}

/// Save an FCM token under users/{uid}/profile/info
Future<void> _saveToken(String uid, String token) async {
  if (uid.isEmpty) return;
  final ref = _db.collection('users').doc(uid).collection('profile').doc('info');

  await ref.set({
    'userId'    : uid,
    'fcmTokens' : FieldValue.arrayUnion([token]),
    'updatedAt' : FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Convenience: call from your widget (e.g., Dashboard) after sign-in:
///
/// @override
/// void initState() {
///   super.initState();
///   final uid = FirebaseAuth.instance.currentUser?.uid;
///   if (uid != null) {
///     initPush(uid);
///   }
/// }
///
/// On web, ensure you have web/firebase-messaging-sw.js with your Firebase config
/// and that you replaced the VAPID key above.
/// Background notifications on Android/iOS are handled by the OS if your
/// message includes a "notification" payload from the server (recommended).
