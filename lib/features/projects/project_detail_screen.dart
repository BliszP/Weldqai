import 'package:flutter/material.dart';
import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/core/design/app_tokens.dart';
import 'package:weldqai_app/core/repositories/project_repository.dart';
import 'package:weldqai_app/core/services/logger_service.dart';
import 'package:weldqai_app/features/projects/create_project_screen.dart';

/// Hub screen for a single project.
///
/// Provides:
///   • Project info (name, client, location, type, dates, status)
///   • "Start New Inspection" entry point → ReportCatalogScreen
///   • Template upload (saves to user's custom schemas, available globally)
///   • Quick stats from the project document
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.userId,
    required this.projectId,
    required this.project,
  });

  final String userId;
  final String projectId;

  /// Pre-loaded project map passed from ProjectsListScreen to avoid an
  /// extra Firestore read on open.  May be refreshed after edits.
  final Map<String, dynamic> project;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late Map<String, dynamic> _project;

  @override
  void initState() {
    super.initState();
    _project = Map<String, dynamic>.from(widget.project);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static const _typeLabels = {
    'pipeline':        'Pipeline',
    'structural':      'Structural',
    'pressure_vessel': 'Pressure Vessel',
    'offshore':        'Offshore',
    'other':           'Other',
  };

  bool get _isOpen => (_project['status'] as String? ?? 'open') == 'open';

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _openEdit() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateProjectScreen(
          projectId: widget.projectId,
          initialData: _project,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == true) {
      // Re-fetch updated project data
      final updated = await ProjectRepository()
          .getProject(widget.userId, widget.projectId);
      if (updated != null && mounted) {
        setState(() => _project = updated);
      }
    }
  }

  Future<void> _toggleStatus() async {
    if (_isOpen) {
      // Close project
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Close Project?'),
          content: Text('Mark "${_project['name']}" as closed?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Close')),
          ],
        ),
      );
      if (confirmed != true) return;
      await ProjectRepository().closeProject(widget.userId, widget.projectId);
    } else {
      // Reopen
      await ProjectRepository().updateProject(
          widget.userId, widget.projectId, {'status': 'open', 'endDate': null});
    }
    // Refresh
    final updated =
        await ProjectRepository().getProject(widget.userId, widget.projectId);
    if (updated != null && mounted) {
      setState(() => _project = updated);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text(
            'This permanently deletes "${_project['name']}". Reports are not deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ProjectRepository()
            .deleteProject(widget.userId, widget.projectId);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        AppLogger.error('❌ Failed to delete project', error: e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme   = Theme.of(context).colorScheme;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final name        = _project['name']       as String? ?? 'Project';
    final client      = _project['clientName'] as String? ?? '';
    final location    = _project['location']   as String? ?? '';
    final type        = _project['type']       as String? ?? 'other';
    final startDate   = _project['startDate']  as String? ?? '';
    final endDate     = _project['endDate']    as String?;
    final reportCount = _project['reportCount'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          // Status chip
          GestureDetector(
            onTap: _toggleStatus,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _isOpen
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _isOpen ? Colors.green : Colors.grey, width: 1),
              ),
              child: Text(
                _isOpen ? 'Open' : 'Closed',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _isOpen ? Colors.green[700] : Colors.grey[600],
                ),
              ),
            ),
          ),
          // Overflow menu
          PopupMenuButton<_Action>(
            tooltip: 'Project options',
            icon: const Icon(Icons.more_vert),
            onSelected: (a) {
              switch (a) {
                case _Action.edit:   _openEdit();
                case _Action.toggle: _toggleStatus();
                case _Action.delete: _delete();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _Action.edit,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit Project'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: _Action.toggle,
                child: ListTile(
                  leading: Icon(
                      _isOpen ? Icons.lock_outlined : Icons.lock_open_outlined),
                  title: Text(_isOpen ? 'Close Project' : 'Reopen Project'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: _Action.delete,
                child: ListTile(
                  leading:
                      const Icon(Icons.delete_outlined, color: Colors.red),
                  title: const Text('Delete',
                      style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),


      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── Project Info ─────────────────────────────────────────────────
          _SectionCard(
            child: InkWell(
              onTap: _openEdit,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 17)),
                        ),
                        Icon(Icons.edit_outlined,
                            size: 16,
                            color: isDark ? Colors.grey[500] : Colors.grey[400]),
                      ],
                    ),
                    if (client.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _InfoRow(Icons.business_outlined, client),
                    ],
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _InfoRow(Icons.location_on_outlined, location),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Chip(
                            _typeLabels[type] ?? 'Other', scheme.primaryContainer,
                            scheme.onPrimaryContainer),
                        if (startDate.isNotEmpty)
                          _Chip('From $startDate',
                              isDark
                                  ? Colors.grey[800]!
                                  : Colors.grey[100]!,
                              isDark
                                  ? Colors.grey[300]!
                                  : Colors.grey[700]!),
                        if (endDate != null && endDate.isNotEmpty)
                          _Chip('To $endDate',
                              isDark
                                  ? Colors.grey[800]!
                                  : Colors.grey[100]!,
                              isDark
                                  ? Colors.grey[300]!
                                  : Colors.grey[700]!),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Quick Stats ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.description_outlined,
                  label: 'Reports Filed',
                  value: '$reportCount',
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: _isOpen
                      ? Icons.lock_open_outlined
                      : Icons.lock_outlined,
                  label: 'Status',
                  value: _isOpen ? 'Active' : 'Closed',
                  color: _isOpen ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Per-type stats ───────────────────────────────────────────────
          _TypeStatsSection(
            userId: widget.userId,
            projectId: widget.projectId,
          ),

          const SizedBox(height: 16),

          // ── Start Inspection ─────────────────────────────────────────────
          _SectionCard(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.add_task,
                    color: scheme.onPrimaryContainer),
              ),
              title: const Text('Start New Inspection',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Pick a schema or use a custom template'),
              trailing: Icon(Icons.chevron_right, color: scheme.primary),
              onTap: () => Navigator.pushNamed(
                context,
                Paths.qcCatalog,
                arguments: {'projectId': widget.projectId},
              ),
            ),
          ),


          const SizedBox(height: 16),

          // ── View All Reports ──────────────────────────────────────────────
          _SectionCard(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.description_outlined, color: Colors.teal),
              ),
              title: const Text('View All Reports',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Browse and manage inspection records'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(
                context,
                Paths.qcCatalog,
                arguments: {'projectId': widget.projectId},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-type stats section ────────────────────────────────────────────────────

/// Reads the `typeStats` map from the project document and renders one row per
/// inspection category that has been used.  Hidden when no stats yet exist.
class _TypeStatsSection extends StatelessWidget {
  const _TypeStatsSection({
    required this.userId,
    required this.projectId,
  });

  final String userId;
  final String projectId;

  static const _labels = {
    'welding_operation': 'Welding',
    'visual_inspection': 'Visual Inspection',
    'ndt_rt':            'NDT (RT)',
    'ndt_ut':            'NDT (UT)',
    'ndt_mpi':           'NDT (MPI)',
    'structural_fillet': 'Structural / Fillet',
    'repairs':           'Repairs',
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, int>>(
      stream: ProjectRepository().watchTypeStats(userId, projectId),
      builder: (context, snap) {
        final stats = snap.data ?? const <String, int>{};
        final entries = stats.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)); // highest first

        if (entries.isEmpty) return const SizedBox.shrink();

        return _SectionCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Inspections by Type',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final e in entries)
                  _TypeStatRow(
                    label: _labels[e.key] ?? e.key.replaceAll('_', ' '),
                    count: e.value,
                    total: stats.values.fold(0, (a, b) => a + b),
                    color: AppTokens.categoryColor(
                      e.key.contains('ndt')        ? 'ndt'
                      : e.key.contains('weld')     ? 'welding'
                      : e.key.contains('visual')   ? 'welding'
                      : e.key.contains('repair')   ? 'welding'
                      : e.key.contains('struct')   ? 'structural'
                      : 'welding',
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TypeStatRow extends StatelessWidget {
  const _TypeStatRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('$count',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Action { edit, toggle, delete }

// ── Small helpers ────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Icon(icon, size: 14,
          color: isDark ? Colors.grey[400] : Colors.grey[600]),
      const SizedBox(width: 6),
      Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600]))),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: color)),
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
