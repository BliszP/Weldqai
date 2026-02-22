// lib/features/project_dashboard_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/core/providers/workspace_provider.dart';
import 'package:weldqai_app/core/services/push_service.dart';
import 'package:weldqai_app/features/sharing/share_access_screen.dart';
import 'package:weldqai_app/features/notifications/notifications_screen.dart';
import 'package:provider/provider.dart';
import 'package:weldqai_app/core/services/subscription_service.dart'; // ✅ ADD THIS
import 'package:weldqai_app/features/account/widgets/upgrade_options_dialog.dart';


/// ---------- Loader typedefs (Futures required; Streams optional) ----------
typedef LoadSummary      = Future<Map<String, dynamic>> Function();
typedef LoadQueuePage    = Future<List<Map<String, dynamic>>> Function();
typedef LoadAlerts       = Future<List<Map<String, dynamic>>> Function();

/// New: schema KPI loaders (return small maps used by the tiles)
typedef LoadKpis = Future<Map<String, dynamic>> Function();

/// Optional streams
typedef StreamMapS  = Stream<Map<String, dynamic>>;
typedef StreamListS = Stream<List<Map<String, dynamic>>>;
typedef StreamKpis = Stream<Map<String, dynamic>>;


/// --------------------------------------------------------------------------
class ProjectDashboardScreen extends StatefulWidget {
  const ProjectDashboardScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.loadSummary,
    required this.loadQueuePage,
    required this.loadAlerts,

    // Optional: live hooks
    this.summaryStream,
    this.alertsStream,
    this.queueStream,

    // Schema KPI hooks (Futures required; Streams optional)
    required this.loadWeldingKpis,
    required this.loadVisualKpis,
    required this.loadNdtKpis,
    required this.loadRepairsKpis,

    this.weldingKpisStream,
    this.visualKpisStream,
    this.ndtKpisStream,
    this.repairsKpisStream,

    // Activity (recent events across reports/chat)
    required this.loadActivity,
    this.activityStream,
  });

  final String userId;
  final String title;

  // Required fallbacks
  final LoadSummary   loadSummary;
  final LoadQueuePage loadQueuePage;
  final LoadAlerts    loadAlerts;

  // Optional live streams
  final StreamMapS?  summaryStream;
  final StreamListS? alertsStream;
  final StreamListS? queueStream;

  // Schema KPI loaders
  final LoadKpis loadWeldingKpis;
  final LoadKpis loadVisualKpis;
  final LoadKpis loadNdtKpis;
  final LoadKpis loadRepairsKpis;

  
  // NEW: optional streams for live tiles
  final StreamKpis? weldingKpisStream;
  final StreamKpis? visualKpisStream;
  final StreamKpis? ndtKpisStream;
  final StreamKpis? repairsKpisStream;

  // Activity
  final Future<List<Map<String, dynamic>>> Function() loadActivity;
  final Stream<List<Map<String, dynamic>>>? activityStream;

  

  @override
  State<ProjectDashboardScreen> createState() => _ProjectDashboardScreenState();
}

enum _DashMenu { account, signOut }


class _ProjectDashboardScreenState extends State<ProjectDashboardScreen> {
  int _page = 1;

  Future<Map<String, dynamic>>           get _summaryF  => widget.loadSummary();
  Future<List<Map<String, dynamic>>>     get _queueF    => widget.loadQueuePage();
  Future<List<Map<String, dynamic>>>     get _alertsF   => widget.loadAlerts();
  Future<List<Map<String, dynamic>>>     get _activityF => widget.loadActivity();

  

  void _prev() { if (_page > 1) setState(() => _page -= 1); }
  void _next() => setState(() => _page += 1);

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      initPush(uid); // from lib/core/services/push_service.dart
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _MainDrawer(userId: widget.userId, userName: widget.title),
      appBar: AppBar(
  title: Consumer<WorkspaceProvider>(
    builder: (context, workspace, _) {
      if (workspace.isViewingOwnWorkspace) {
        return Text(widget.title);
      }
      // Viewing a shared workspace
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Shared Workspace',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            workspace.activeWorkspaceOwnerEmail ?? widget.title,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  ),
  actions: [
    // Show "Back to My Workspace" button when viewing shared workspace
   Consumer<WorkspaceProvider>(
  builder: (context, workspace, _) {
    if (!workspace.isViewingOwnWorkspace) {
      return IconButton(
        icon: const Icon(Icons.home),
        tooltip: 'Back to my workspace',
        onPressed: () {
          workspace.switchToMyWorkspace();
          // Force a full rebuild by popping all routes and pushing fresh
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/dashboard',
            (route) => false,
          );
        },
      );
    }
    return const SizedBox.shrink();
  },
),
    _NotificationsBell(uid: widget.userId),
    IconButton(
      tooltip: 'Share & Access',
      icon: const Icon(Icons.group_add),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ShareAccessScreen()),
        );
      },
    ),
    PopupMenuButton<_DashMenu>(
      tooltip: 'Menu',
      icon: const Icon(Icons.more_vert),
      onSelected: (choice) {
        switch (choice) {
          case _DashMenu.account:
            Navigator.pushNamed(context, Paths.accountSettings);
            break;
          case _DashMenu.signOut:
            // Reset workspace before signing out
            context.read<WorkspaceProvider>().reset();
            Navigator.pushNamedAndRemoveUntil(
              context,
              Paths.welcome,
              (r) => false,
            );
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _DashMenu.account,
          child: Text('Account Settings'),
        ),
        PopupMenuItem(
          value: _DashMenu.signOut,
          child: Text('Sign out'),
        ),
      ],
    ),
  ],
),

      body: SafeArea(
        child: Column(  // ✅ CHANGED: Wrap in Column
          children: [
      // ✅ ADD: Trial banner
   // ✅ FIXED (auto-updates in real-time):
StreamBuilder<SubscriptionStatus>(
  stream: SubscriptionService().watchStatus(), // ← Use stream instead
  builder: (context, snapshot) {
    if (!snapshot.hasData) return SizedBox.shrink();
    
    final status = snapshot.data!;
    
    // Show banner only for trial or expired trial
    if (status.type != SubscriptionType.trial && 
        status.type != SubscriptionType.trialExpired) {
      return SizedBox.shrink();
    }
    
    final remaining = status.reportsRemaining ?? 0;
    final days = status.daysRemaining;
    final isExpired = status.type == SubscriptionType.trialExpired;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isExpired 
          ? Colors.red[100]
          : remaining <= 1 
              ? Colors.orange[100]
              : Colors.blue[50],
      child: Row(
        children: [
          Icon(
            isExpired ? Icons.block : Icons.info_outline,
            color: isExpired 
                ? Colors.red 
                : remaining <= 1 ? Colors.orange : Colors.blue,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              isExpired
                  ? 'Trial ended - Upgrade to continue creating reports'
                  : '$remaining reports left${days != null ? ' • $days days remaining' : ''}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isExpired ? Colors.red[900] : null,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              showUpgradeOptionsDialog(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isExpired ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('Upgrade'),
          ),
        ],
      ),
    );
  },
),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final isWide = c.maxWidth >= 1100;
                  final isMedium = c.maxWidth >= 760;
    
                  // ---------- Overview KPIs ----------
                  final overview = _OverviewStrip(
                    summaryF: _summaryF,
                    summaryS: widget.summaryStream,
                  );
    
                  // ---------- Schema tiles ----------
                  final schemaGrid = _SchemaGrid(
                    loadWeldingKpis: widget.loadWeldingKpis,
                    loadVisualKpis:  widget.loadVisualKpis,
                    loadNdtKpis:     widget.loadNdtKpis,
                    loadRepairsKpis: widget.loadRepairsKpis,
                    weldingKpisS: widget.weldingKpisStream,
                    visualKpisS:  widget.visualKpisStream,
                    ndtKpisS:     widget.ndtKpisStream,
                    repairsKpisS: widget.repairsKpisStream,
                    
                  );
    
                  // ---------- Activity & Alerts ----------
                  final activityAlerts = _ActivityAlertsRow(
                    activityF: _activityF,
                    activityS: widget.activityStream,
                    alertsF: _alertsF,
                    alertsS: widget.alertsStream,
                  );
    
                  // ---------- Work queue ----------
                  final queue = _WorkQueueCard(
                    queueF: _queueF,
                    queueS: widget.queueStream,
                    page: _page,
                    onPrev: _prev,
                    onNext: _next,
                  );
    
                  if (isWide) {
                    return ListView(
                      children: [
                        overview,
                        const SizedBox(height: 16),
                        schemaGrid,
                        const SizedBox(height: 16),
                        activityAlerts,
                        const SizedBox(height: 16),
                        queue,
                      ],
                    );
                  }
                  if (isMedium) {
                    return ListView(
                      children: [
                        overview,
                        const SizedBox(height: 12),
                        schemaGrid,
                        const SizedBox(height: 12),
                        activityAlerts,
                        const SizedBox(height: 12),
                        queue,
                      ],
                    );
                  }
                  // narrow
                  return ListView(
                    children: [
                      overview,
                      const SizedBox(height: 12),
                      schemaGrid,
                      const SizedBox(height: 12),
                      activityAlerts,
                      const SizedBox(height: 12),
                      queue,
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}



/// ###########################################################################
/// Drawer
/// ###########################################################################
class _MainDrawer extends StatelessWidget {
  const _MainDrawer({required this.userId, required this.userName});
  final String userId;
  final String userName;

  void _go(BuildContext context, String route, {Map<String, dynamic>? args}) {
    final nav = Navigator.of(context);
    nav.pop(); // close drawer first
    Future.microtask(() {
      nav.pushNamed(route, arguments: args);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WeldQAi', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(userName, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              onTap: () => _go(context, Paths.dashboard),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('QC Reports'),
              onTap: () => _go(context, Paths.qcCatalog),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Visualization'),
              onTap: () => _go(context, Paths.visualizationHome),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Chat'),
              onTap: () => _go(context, Paths.chat),
            ),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Account Settings'),
              onTap: () => _go(context, Paths.accountSettings),
            ),

            ListTile(
  leading: const Icon(Icons.exit_to_app),
  title: const Text('Sign out'),
  onTap: () {
    // Reset workspace before signing out
    context.read<WorkspaceProvider>().reset();
    Navigator.pushNamedAndRemoveUntil(
      context,
      Paths.welcome,
      (r) => false,
    );
  },
),
          ],
        ),
      ),
    );
  }
}

/// ###########################################################################
/// Overview strip (Open Welds, NDT Pending, Repairs, Completed)
/// ###########################################################################
class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip({required this.summaryF, this.summaryS});
  final Future<Map<String, dynamic>> summaryF;
  final Stream<Map<String, dynamic>>? summaryS;

  Map<String, num> _normalize(Map<String, dynamic> m) {
    num pick(List<String> keys) {
      for (final k in keys) {
        if (m.containsKey(k)) {
          final val = m[k];
          if (val is num) return val;
        }
      }
      return 0;
    }

    return {
      'Open Welds' : pick(['openWelds', 'Open Welds']),
      'NDT Pending': pick(['ndtPending', 'NDT Pending']),
      'Repairs'    : pick(['repairs', 'repairsOpen', 'Repairs']),
      'Completed'  : pick(['completed', 'Completed']),
    };
  }

  @override
  Widget build(BuildContext context) {
    Widget body(Map<String, dynamic> source) {
      final m = _normalize(source);
      return Wrap(
        spacing: 12, runSpacing: 12,
        children: [
          _kpi('Open Welds',     (m['Open Welds'] ?? 0).toInt()),
          _kpi('NDT Pending',    (m['NDT Pending'] ?? 0).toInt()),
          _kpi('Repairs',        (m['Repairs'] ?? 0).toInt()),
          _kpi('Completed',      (m['Completed'] ?? 0).toInt()),
        ],
      );
    }

    if (summaryS != null) {
      return StreamBuilder<Map<String, dynamic>>(
        stream: summaryS,
        builder: (_, s) {
          if (!s.hasData && s.connectionState == ConnectionState.waiting) {
            return const _CardShell(child: Center(child: CircularProgressIndicator()));
          }
          return _CardShell(
            title: 'Overview',
            child: body(s.data ?? const <String, dynamic>{}),
          );
        },
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: summaryF,
      builder: (_, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const _CardShell(child: Center(child: CircularProgressIndicator()));
        }
        return _CardShell(
          title: 'Overview',
          child: body(s.data ?? const <String, dynamic>{}),
        );
      },
    );
  }

  Widget _kpi(String label, int value) {
    final t = value.toString();
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// ###########################################################################
/// Schema KPI grid (Welding / Visual / NDT / Repairs)
/// ###########################################################################
class _SchemaGrid extends StatelessWidget {
  const _SchemaGrid({
    required this.loadWeldingKpis,
    required this.loadVisualKpis,
    required this.loadNdtKpis,
    required this.loadRepairsKpis,
    this.weldingKpisS,
    this.visualKpisS,
    this.ndtKpisS,
    this.repairsKpisS,
  });

  final LoadKpis loadWeldingKpis;
  final LoadKpis loadVisualKpis;
  final LoadKpis loadNdtKpis;
  final LoadKpis loadRepairsKpis;

  final StreamKpis? weldingKpisS;
  final StreamKpis? visualKpisS;
  final StreamKpis? ndtKpisS;
  final StreamKpis? repairsKpisS;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _SchemaTile(title: 'Welding',           loader: loadWeldingKpis, stream: weldingKpisS),
      _SchemaTile(title: 'Visual Inspection', loader: loadVisualKpis,  stream: visualKpisS),
      _SchemaTile(title: 'NDT',               loader: loadNdtKpis,     stream: ndtKpisS),
      _SchemaTile(title: 'Repairs',           loader: loadRepairsKpis, stream: repairsKpisS),
    ];

    return LayoutBuilder(
      builder: (ctx, c) {
        final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 760 ? 2 : 1);
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: tiles,
        );
      },
    );
  }
}

class _SchemaTile extends StatelessWidget {
  const _SchemaTile({required this.title, required this.loader, this.stream});
  final String title;
  final Future<Map<String, dynamic>> Function() loader;
  final Stream<Map<String, dynamic>>? stream;

  @override
  Widget build(BuildContext context) {
    if (stream != null) {
      return StreamBuilder<Map<String, dynamic>>(
        stream: stream,
        builder: (_, s) {
          if (!s.hasData && s.connectionState == ConnectionState.waiting) {
            return const _CardShell(child: Center(child: CircularProgressIndicator()));
          }
          final m = s.data ?? const <String, dynamic>{};
          return _tileBody(title, m);
        },
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: loader(),
      builder: (_, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const _CardShell(child: Center(child: CircularProgressIndicator()));
        }
        final m = s.data ?? const <String, dynamic>{};
        return _tileBody(title, m);
      },
    );
  }

Widget _tileBody(String title, Map<String, dynamic> m) {
  final rows = m.keys.toList()..sort();
  
  // Define colors per section
  Color getAccentColor(String title) {
    switch (title) {
      case 'Welding': return Colors.blue;
      case 'Visual Inspection': return Colors.orange;
      case 'NDT': return Colors.purple;
      case 'Repairs': return Colors.red;
      default: return Colors.grey;
    }
  }
  
  return Card(
    margin: const EdgeInsets.all(8),
    child: Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: getAccentColor(title), width: 4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final k in rows.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: _kv(k, _formatNum(m[k])),
            ),
          if (rows.isEmpty) const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No data'),
          ),
        ],
      ),
    ),
  );
}

  Widget _kv(String k, String v) => Row(
        children: [
          Expanded(child: Text(k, overflow: TextOverflow.ellipsis)),
          Text(v),
        ],
      );

  String _formatNum(dynamic n) {
    if (n == null) return '0';
    if (n is int) return n.toString();
    if (n is num) return n.toDouble().toStringAsFixed(1);
    return n.toString();
  }
}


/// ###########################################################################
/// Activity & Alerts
/// ###########################################################################
class _ActivityAlertsRow extends StatelessWidget {
  const _ActivityAlertsRow({
    required this.activityF,
    this.activityS,
    required this.alertsF,
    this.alertsS,
  });

  final Future<List<Map<String, dynamic>>> activityF;
  final Stream<List<Map<String, dynamic>>>? activityS;
  final Future<List<Map<String, dynamic>>> alertsF;
  final Stream<List<Map<String, dynamic>>>? alertsS;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final stacked = c.maxWidth < 1000;
      final left = _ActivityCard(activityF: activityF, activityS: activityS);
      final right = _AlertsCard(alertsF: alertsF, alertsS: alertsS);

      if (stacked) {
        return Column(
          children: [
            left,
            const SizedBox(height: 12),
            right,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
    });
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activityF, this.activityS});
  final Future<List<Map<String, dynamic>>> activityF;
  final Stream<List<Map<String, dynamic>>>? activityS;

  @override
  Widget build(BuildContext context) {
    if (activityS != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: activityS,
        builder: (_, s) => _card(context, s.data),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: activityF,
      builder: (_, s) => _card(context, s.data),
    );
  }

Widget _card(BuildContext context, List<Map<String, dynamic>>? data) {
  final allItems = data ?? const <Map<String, dynamic>>[];
  
  // ✅ Filter by dashboard status (manual management)
  final items = allItems.where((item) {
    final dashStatus = (item['status'] ?? 'active').toString().toLowerCase();
    // Show only "active" items (exclude completed/dismissed)
    return dashStatus == 'active';
  }).toList();
    return Card(
      margin: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Colors.green, width: 4),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            (items.isEmpty)
                ? const Text('No recent activity')
                : Column(
                    children: [
                      for (final it in items.take(6))
                        ListTile(
                          dense: true,
                          title: Text('${it['title'] ?? 'Activity'}'),
                          subtitle: (it['subtitle'] != null) 
                              ? Text('${it['subtitle']}') 
                              : null,
                          trailing: _buildActivityMenu(context, it), // ✅ ADD THIS
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  // ✅ ADD THIS METHOD - Three-dot menu for activity items
  Widget _buildActivityMenu(BuildContext context, Map<String, dynamic> item) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'Actions',
      onSelected: (action) async {
        await _handleActivityAction(context, item, action);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'complete',
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: Colors.green),
              SizedBox(width: 8),
              Text('Mark Complete'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'dismiss',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 18),
              SizedBox(width: 8),
              Text('Dismiss'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  // ✅ ADD THIS METHOD - Handle menu actions
  Future<void> _handleActivityAction(
    BuildContext context,
    Map<String, dynamic> item,
    String action,
  ) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final itemId = item['id']?.toString();
    if (itemId == null) return;

    try {
      if (action == 'delete') {
        // Confirm deletion
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Activity Item'),
            content: const Text('Remove this item from activity stream?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;

        // Delete the item
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('activity')
            .doc(itemId)
            .delete();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Activity item deleted')),
          );
        }
      } else {
        // Update status (complete or dismiss)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('activity')
            .doc(itemId)
            .update({
          'status': action == 'complete' ? 'completed' : 'dismissed',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
          'statusUpdatedBy': userId,
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Marked as ${action == 'complete' ? 'complete' : 'dismissed'}'),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}


class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.alertsF, this.alertsS});
  final Future<List<Map<String, dynamic>>> alertsF;
  final Stream<List<Map<String, dynamic>>>? alertsS;

  @override
  Widget build(BuildContext context) {
    if (alertsS != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: alertsS,
        builder: (_, s) => _card(context, s.data),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: alertsF,
      builder: (_, s) => _card(context, s.data),
    );
  }

 Widget _card(BuildContext context, List<Map<String, dynamic>>? data) {
  final allItems = data ?? const <Map<String, dynamic>>[];
  
  // ✅ Filter by dashboard status
  final items = allItems.where((item) {
    final dashStatus = (item['status'] ?? 'active').toString().toLowerCase();
    // Show only "active" items
    return dashStatus == 'active';
  }).toList();
    return Card(
      margin: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Colors.amber.shade700, width: 4),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Alerts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                )
              ],
            ),
            const SizedBox(height: 8),
            (items.isEmpty)
                ? const Text('No alerts.')
                : Column(
                    children: [
                      for (final it in items.take(6))
                        ListTile(
                          dense: true,
                          title: Text('${it['title'] ?? 'Alert'}'),
                          subtitle: () {
                            final tText = (it['timeText'] ?? it['time'])?.toString();
                            return (tText != null && tText.isNotEmpty) ? Text(tText) : null;
                          }(),
                          trailing: _buildAlertMenu(context, it), // ✅ ADD THIS
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  // ✅ ADD THIS METHOD - Three-dot menu for alerts
  Widget _buildAlertMenu(BuildContext context, Map<String, dynamic> item) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'Actions',
      onSelected: (action) async {
        await _handleAlertAction(context, item, action);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'resolve',
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: Colors.green),
              SizedBox(width: 8),
              Text('Mark Resolved'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'acknowledge',
          child: Row(
            children: [
              Icon(Icons.visibility, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text('Acknowledge'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'dismiss',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 18),
              SizedBox(width: 8),
              Text('Dismiss'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  // ✅ ADD THIS METHOD - Handle alert actions
  Future<void> _handleAlertAction(
    BuildContext context,
    Map<String, dynamic> item,
    String action,
  ) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final itemId = item['id']?.toString();
    if (itemId == null) return;

    try {
      if (action == 'delete') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Alert'),
            content: const Text('Remove this alert?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('alerts')
            .doc(itemId)
            .delete();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Alert deleted')),
          );
        }
      } else {
        // Update status
        String newStatus;
        switch (action) {
          case 'resolve':
            newStatus = 'resolved';
            break;
          case 'acknowledge':
            newStatus = 'acknowledged';
            break;
          case 'dismiss':
            newStatus = 'dismissed';
            break;
          default:
            return;
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('alerts')
            .doc(itemId)
            .update({
          'status': newStatus,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
          'statusUpdatedBy': userId,
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ Alert $newStatus')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
// In project_dashboard_screen.dart (add below your other private widgets)
class _NotificationsBell extends StatelessWidget {
  const _NotificationsBell({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final metaRef = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('meta').doc('meta');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: metaRef.snapshots(includeMetadataChanges: true),
      builder: (context, s) {
        final unread = (s.data?.data()?['inboxUnread'] ?? 0) as num;
        final showDot = unread > 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_none),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => NotificationsScreen(userId: uid)),
                );
              },
            ),
            if (showDot)
              Positioned(
                right: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle,
                  ),
                  child: Text(
                    (unread > 99 ? '99+' : unread.toInt().toString()),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}


/// ###########################################################################
/// Work queue
/// ###########################################################################
class _WorkQueueCard extends StatelessWidget {
  const _WorkQueueCard({
    required this.queueF,
    this.queueS,
    required this.page,
    required this.onPrev,
    required this.onNext,
  });

  final Future<List<Map<String, dynamic>>> queueF;
  final Stream<List<Map<String, dynamic>>>? queueS;
  final int page;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    if (queueS != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: queueS,
        builder: (_, s) => _card(context, s.data ?? const <Map<String, dynamic>>[], live: true),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: queueF,
      builder: (_, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const _CardShell(child: Center(child: CircularProgressIndicator()));
        }
        return _card(context, s.data ?? const <Map<String, dynamic>>[]);
      },
    );
  }

  Widget _card(BuildContext context, List<Map<String, dynamic>> allRows, {bool live = false}) {
  // ✅ FILTER OUT completed/dismissed items
  final rows = allRows.where((item) {
    final status = (item['status'] ?? 'active').toString().toLowerCase();
    return status != 'completed' && status != 'dismissed' && status != 'closed';
  }).toList();
    return Card(
      margin: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Colors.indigo, width: 4),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Work Queue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No queued items.'),
                ),
              )
            else
              Column(
                children: [
                  for (final r in rows)
                    ListTile(
                      dense: true,
                      title: Text('${r['title'] ?? 'Item'}'),
                      subtitle: Text([
                        if (r['line1'] != null) '${r['line1']}',
                        if (r['line2'] != null) '${r['line2']}',
                      ].join(' • ')),
                      trailing: _buildQueueMenu(context, r), // ✅ CHANGE THIS
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            const SizedBox(height: 8),
            if (!live)
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (page > 1) ? onPrev : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Prev'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next'),
                  ),
                  const Spacer(),
                  Text('Page $page'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ✅ ADD THIS METHOD - Three-dot menu for queue items
  Widget _buildQueueMenu(BuildContext context, Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? '';
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getStatusColor(status).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _getStatusColor(status),
              ),
            ),
          ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          tooltip: 'Actions',
          onSelected: (action) async {
            await _handleQueueAction(context, item, action);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'complete',
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Mark Complete'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'in_progress',
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, size: 18, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('In Progress'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'pending',
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 18, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Mark Pending'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'dismiss',
              child: Row(
                children: [
                  Icon(Icons.visibility_off, size: 18),
                  SizedBox(width: 8),
                  Text('Dismiss'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
      case 'closed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // ✅ ADD THIS METHOD - Handle queue actions
  Future<void> _handleQueueAction(
    BuildContext context,
    Map<String, dynamic> item,
    String action,
  ) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final itemId = item['id']?.toString();
    if (itemId == null) return;

    try {
      if (action == 'delete') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Queue Item'),
            content: const Text('Remove this item from queue?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('queue')
            .doc(itemId)
            .delete();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Queue item deleted')),
          );
        }
      } else {
        // Update status
        String newStatus;
        switch (action) {
          case 'complete':
            newStatus = 'completed';
            break;
          case 'in_progress':
            newStatus = 'in_progress';
            break;
          case 'pending':
            newStatus = 'pending';
            break;
          case 'dismiss':
            newStatus = 'dismissed';
            break;
          default:
            return;
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('queue')
            .doc(itemId)
            .update({
          'status': newStatus,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
          'statusUpdatedBy': userId,
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ Status updated to $newStatus')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}


/// ---------- Small Card shell ----------
class _CardShell extends StatelessWidget {
  const _CardShell({this.title, required this.child});
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
