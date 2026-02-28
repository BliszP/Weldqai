// ignore_for_file: non_constant_identifier_names, unused_local_variable

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/core/providers/workspace_provider.dart';

// Screens
import 'package:weldqai_app/features/welcome/welcome_screen.dart';
import 'package:weldqai_app/features/auth/auth_screen.dart';
import 'package:weldqai_app/features/projects/project_dashboard_screen.dart';
import 'package:weldqai_app/features/reports/base/dynamic_report_screen.dart';
import 'package:weldqai_app/features/account/account_settings_screen.dart';
import 'package:weldqai_app/features/chat/project_chat_screen.dart';
import 'package:weldqai_app/features/visualization/visualization_home_screen.dart';
import 'package:weldqai_app/features/visualization/visualization_kpi_screen.dart';
import 'package:weldqai_app/features/account/complete_profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:weldqai_app/features/reports/base/report_catalog_screen.dart';


// NEW: User-based repository
import 'package:weldqai_app/core/repositories/user_data_repository.dart';
import 'package:weldqai_app/core/repositories/metrics_repository.dart';
import 'package:weldqai_app/features/notifications/notifications_screen.dart';
import 'package:weldqai_app/features/offline/offline_mode_screen.dart';
import 'package:weldqai_app/features/sharing/share_access_screen.dart';
import 'package:weldqai_app/features/projects/projects_list_screen.dart';
import 'package:weldqai_app/features/projects/create_project_screen.dart';
import 'package:weldqai_app/features/projects/project_detail_screen.dart';
import 'package:weldqai_app/features/reports/reports_history_screen.dart';
import 'package:weldqai_app/features/account/audit_log_screen.dart';

final UserDataRepository _userDataRepo = UserDataRepository();
final MetricsRepository _metricsRepo = MetricsRepository();
final FirebaseAuth _auth = FirebaseAuth.instance;


class AppRouter {
  /// Helper to get current user or redirect to auth
  static String? _getCurrentUserId() {
    return _auth.currentUser?.uid;
  }

  /// Use with MaterialApp.onGenerateRoute
  static Route<dynamic> ApponGenerateRoute(RouteSettings settings) {
    final String name = settings.name ?? '';
    final Map<String, dynamic> args = _asMap(settings.arguments);

    // Check authentication for protected routes
    final protectedRoutes = [
      Paths.dashboard,
      Paths.qcCatalog,
      Paths.dynamicReport,
      Paths.visualizationHome,
      Paths.visualizationKpi,
      Paths.chat,
      Paths.accountSettings,
    ];

    if (protectedRoutes.contains(name)) {
      final userId = _getCurrentUserId();
      if (userId == null) {
        // Not authenticated, redirect to auth
        return MaterialPageRoute(
          builder: (_) => const AuthScreen(),
          settings: settings,
        );
      }
    }

    switch (name) {
      // ----------------- Auth / Welcome -----------------
      case Paths.welcome:
        return MaterialPageRoute(
          builder: (_) => const WelcomeScreen(),
          settings: settings,
        );

      case Paths.auth: {
  final args = _asMap(settings.arguments);
  final initialMode = args['initialMode'] as String?;
  
  return MaterialPageRoute(
    builder: (_) => AuthScreen(initialMode: initialMode),
    settings: settings,
  );
}
      // ----------------- Dashboard (Main App Screen) ----
case Paths.dashboard: {
  final userId = _getCurrentUserId();
  if (userId == null) {
    return MaterialPageRoute(
      builder: (_) => const AuthScreen(),
      settings: settings,
    );
  }
  
  return MaterialPageRoute(
    settings: settings,
    builder: (context) {
      // ✅ SAFE: Only access workspace after authentication check
      final workspaceProvider = Provider.of<WorkspaceProvider>(context, listen: true);
      final workspace = workspaceProvider.activeWorkspace; userId;
      final displayName = _auth.currentUser?.displayName
          ?? _auth.currentUser?.email?.split('@').first
          ?? 'Dashboard';

      return ProjectDashboardScreen(
        userId: workspace, // Use workspace instead of current user's UID
        title: displayName,

        // futures (fallbacks)
        loadSummary: () => _userDataRepo.summaryStream(workspace).first,
        loadQueuePage: () => _userDataRepo.loadQueuePage(workspace),
        loadAlerts: () => _userDataRepo.loadAlerts(workspace),
        loadActivity: () => _userDataRepo.loadActivity(workspace),
        loadWeldingKpis: () => _userDataRepo.loadWeldingKpis(workspace),
        loadVisualKpis: () => _userDataRepo.loadVisualKpis(workspace),
        loadNdtKpis: () => _userDataRepo.loadNdtKpis(workspace),
        loadRepairsKpis: () => _userDataRepo.loadRepairsKpis(workspace),

        // live streams (preferred)
        summaryStream: _userDataRepo.summaryStream(workspace),
        alertsStream: _userDataRepo.alertsStream(workspace),
        queueStream: _userDataRepo.queueStream(workspace),
        activityStream: _userDataRepo.activityStream(workspace),
        weldingKpisStream: _metricsRepo.dashboardWeldingKpisStream(workspace),
        visualKpisStream: _metricsRepo.dashboardVisualKpisStream(workspace),
        ndtKpisStream: _metricsRepo.dashboardNdtKpisStream(workspace),
        repairsKpisStream: _metricsRepo.dashboardRepairsKpisStream(workspace),
      );
    },
  );
}

      // ----------------- Notifications -----------------
// in your onGenerateRoute switch:
case Paths.notifications: {
  final userId = _auth.currentUser!.uid;
  return MaterialPageRoute(
    builder: (_) => NotificationsScreen(userId: userId),
    settings: settings,
  );
}

      // ----------------- Complete Profile ---------------
      case Paths.completeProfile:
        return MaterialPageRoute(
          builder: (_) => const CompleteProfileScreen(),
          settings: settings,
        );

      

// Then in your switch statement, REPLACE the entire qcCatalog case with:
case Paths.qcCatalog: {
  return MaterialPageRoute(
    settings: settings,
    builder: (context) {
      final workspace = Provider.of<WorkspaceProvider>(context, listen: false).activeWorkspace;
      final projectId = args['projectId'] as String?;
      return ReportCatalogScreen(userId: workspace, projectId: projectId);
    },
  );
}

case Paths.dynamicReport: {
  final String schemaId = (args['schemaId'] ?? 'welding_operation').toString();
  final String schemaTitle = (args['schemaTitle'] ?? 'Welding Operation').toString();
  final String? reportId = args['reportId'] as String?;
  final String? projectId = args['projectId'] as String?;

  return MaterialPageRoute(
    settings: settings,
    builder: (context) {
      final workspace = args['userId'] as String? ??
                       args['workspace'] as String? ??
                       Provider.of<WorkspaceProvider>(context, listen: false).activeWorkspace;

      return DynamicReportScreen(
        userId: workspace,
        schemaId: schemaId,
        schemaTitle: schemaTitle,
        reportId: reportId,
        projectId: projectId,
      );
    },
  );
}
      // ---------------- Visualization Home ----------------
      case Paths.visualizationHome: {
  return MaterialPageRoute(
    builder: (context) {
      final workspace = Provider.of<WorkspaceProvider>(context, listen: false).activeWorkspace;
      
      return VisualizationHomeScreen(
        userId: workspace,
        loadKpis: (String uid, DateTimeRange? range) =>
            _metricsRepo.loadOverviewKpis(uid, range),
        loadKpisStream: (String uid, DateTimeRange? range) =>
            _metricsRepo.overviewKpisStream(uid, range),
        onOpenKpis: () {
          Navigator.pushNamed(context, Paths.visualizationKpi);
        },
      );
    },
    settings: settings,
  );
}

      // ---------------- Visualization KPI (full charts) ---------------
  case Paths.visualizationKpi: {
  return MaterialPageRoute(
    builder: (context) {
      final workspace = Provider.of<WorkspaceProvider>(context, listen: false).activeWorkspace;
      
      return VisualizationKpiScreen(
        userId: workspace,
        repo: _metricsRepo,
      );
    },
    settings: settings,
  );
}

// ----------------- Chat --------------------
case Paths.chat: {
  final String channelId = (args['channelId'] as String?) ?? 'general';

  return MaterialPageRoute(
    builder: (context) {
      final workspace = Provider.of<WorkspaceProvider>(context, listen: false).activeWorkspace;
      
      return ProjectChatScreen(
        userId: workspace, // Already using workspace
        channelId: channelId,
      );
    },
    settings: settings,
  );
}

// ----------------- Collaboration ----------------
case Paths.collaboration:
  return MaterialPageRoute(
    settings: settings,
    builder: (_) => const ShareAccessScreen(),
  );

// ----------------- Account Settings --------------
      // ----------------- Account Settings --------------
      case Paths.accountSettings: {
        final userId = _getCurrentUserId()!;
        
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AccountSettingsScreen(userId: userId),
        );
      }

      // ----------------- Offline mode ------------------
      case Paths.offline:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const OfflineModeScreen(),
        );

      // ----------------- Projects list -----------------
      case Paths.projects: {
        final userId = _getCurrentUserId()!;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ProjectsListScreen(userId: userId),
        );
      }

      // ----------------- Create / edit project ---------
      case Paths.createProject:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CreateProjectScreen(),
          fullscreenDialog: true,
        );

      // ----------------- Project detail ----------------
      case Paths.projectDetail: {
        final userId    = _getCurrentUserId()!;
        final projectId = args['projectId'] as String;
        final project   = args['project']   as Map<String, dynamic>;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ProjectDetailScreen(
            userId:    userId,
            projectId: projectId,
            project:   project,
          ),
        );
      }

      // ----------------- Report history ---------------
      case Paths.reportsHistory: {
        final userId      = _getCurrentUserId()!;
        final projectId   = args['projectId']   as String?;
        final projectName = args['projectName'] as String?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ReportsHistoryScreen(
            userId:      userId,
            projectId:   projectId,
            projectName: projectName,
          ),
        );
      }

      // ----------------- Audit log --------------------
      case Paths.auditLog: {
        final userId = _getCurrentUserId()!;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AuditLogScreen(userId: userId),
        );
      }

      // ----------------- Fallback ----------------------
      default:
        return MaterialPageRoute(
          builder: (_) => const WelcomeScreen(),
          settings: settings,
        );
    }
  }

  static Map<String, dynamic> _asMap(Object? a) {
    if (a is Map<String, dynamic>) return a;
    if (a is Map) return Map<String, dynamic>.from(a);
    return <String, dynamic>{};
  }
}