import 'dart:async' show unawaited;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
//import 'package:firebase_performance/firebase_performance.dart';

import 'package:weldqai_app/app/app_theme.dart';
import 'package:weldqai_app/core/services/analytics_service.dart';
import 'package:weldqai_app/core/providers/workspace_provider.dart';
import 'package:weldqai_app/core/services/theme_controller.dart';
import 'package:weldqai_app/app/router.dart';
import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/firebase_options.dart';
import 'package:weldqai_app/core/services/sync_service.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:weldqai_app/core/repositories/user_data_repository.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:weldqai_app/core/services/notification_service.dart';
import 'package:weldqai_app/core/services/logger_service.dart';
import 'package:weldqai_app/core/services/error_service.dart';

const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.tracesSampleRate = 0.2;   // 20% of transactions
      options.profilesSampleRate = 0.1; // 10% of sampled transactions
      options.attachScreenshot = true;
      options.attachViewHierarchy = true;
    },
    appRunner: _appRunner,
  );
}

Future<void> _appRunner() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global Flutter framework error handler (e.g. widget build errors)
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.fatal('Flutter framework error', error: details.exception, stackTrace: details.stack);
    unawaited(Sentry.captureException(details.exception, stackTrace: details.stack));
  };

  // Global platform/isolate error handler (unhandled async exceptions)
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.fatal('Platform dispatcher error', error: error, stackTrace: stack);
    unawaited(Sentry.captureException(error, stackTrace: stack));
    return true;
  };

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ Initialize Firebase Performance Monitoring
  //FirebasePerformance performance = FirebasePerformance.instance;

  // ✅ Enable performance collection (optional but recommended)
  // await performance.setPerformanceCollectionEnabled(true);

  await FirebaseAppCheck.instance.activate(
    webProvider: ReCaptchaV3Provider(
      '6LfvvcsrAAAAAERs1_2gxRLovLsi-W5-VqLkcCGB',
    ),
    androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.appAttest,
  );

  // Firestore persistence settings are configured by SyncService.init()
  // which reads the user's preference from SharedPreferences. Do NOT call
  // FirebaseFirestore.instance.settings here — a second call throws on web.
  await ThemeController.i.load();
  await SyncService().init(); // ← sets Firestore.settings once
  runApp(const ProviderScope(child: WeldQAiApp()));
}

class WeldQAiApp extends StatelessWidget {
  const WeldQAiApp({super.key});

  // ✅ Create analytics instance and observer
  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  static FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: analytics);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WorkspaceProvider(),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.i.themeMode,
        builder: (_, mode, __) {
          return MaterialApp(
            title: 'WeldQAi',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            onGenerateRoute: AppRouter.ApponGenerateRoute,
            // ✅ Add analytics observer for automatic screen tracking
            navigatorObservers: [observer],
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

/// Handles initial routing based on auth state
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user is logged in, initialize their profile and go to dashboard
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;

          // Initialize user profile on first login (fire-and-forget; errors handled internally)
          unawaited(_initializeUserProfile(user));

          // Navigate to dashboard. Subscription stream starts automatically
          // when screens first watch subscriptionStatusProvider (Riverpod).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(Navigator.of(context).pushReplacementNamed(Paths.dashboard));
          });

          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // User signed out - reset workspace
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // ✅ Remove FCM token
          unawaited(NotificationService().removeToken());

          // ✅ Log sign out and clear analytics user
          unawaited(AnalyticsService.logSignOut());
          unawaited(AnalyticsService.clearUser());

          // ✅ Clear Sentry user context
          unawaited(ErrorService.clearUser());

          try {
            context.read<WorkspaceProvider>().reset();
          } catch (e) {
            // Provider might not be available in some cases
            AppLogger.debug('Could not reset workspace: $e');
          }

          unawaited(Navigator.of(context).pushReplacementNamed(Paths.welcome));
        });

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Future<void> _initializeUserProfile(User user) async {
    try {
      final repo = UserDataRepository();
      await repo.initializeUserProfile(
        userId: user.uid,
        email: user.email ?? '',
        displayName: user.displayName,
      );

      // ✅ Set user for analytics
      await AnalyticsService.setUser(
        user.uid,
        email: user.email,
        displayName: user.displayName,
      );

      // ✅ Set user context for Sentry
      await ErrorService.setUser(user.uid, email: user.email, displayName: user.displayName);

      // ✅ INITIALIZE NOTIFICATIONS
      await NotificationService().initialize(user.uid);

      // ✅ Log sign in event
      await AnalyticsService.logSignIn('email');
    } catch (e, st) {
      AppLogger.error('❌ Error initializing user profile', error: e, stackTrace: st);
      await ErrorService.captureException(e, stackTrace: st, context: 'initializeUserProfile');
    }
  }
}
