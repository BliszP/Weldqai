import 'package:flutter/material.dart';
import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/core/repositories/project_repository.dart';
import 'package:weldqai_app/features/projects/create_project_screen.dart';

/// Displays all projects for the authenticated user.
///
/// Filter bar: Open | Closed | All
/// Each project card shows name, client, location, type chip, status, dates,
/// and report count. Tapping opens QC Catalog filtered to that project
/// (projectId is passed for future use).
class ProjectsListScreen extends StatefulWidget {
  const ProjectsListScreen({super.key, required this.userId});
  final String userId;

  @override
  State<ProjectsListScreen> createState() => _ProjectsListScreenState();
}

class _ProjectsListScreenState extends State<ProjectsListScreen> {
  /// null = All, 'open' = Open, 'closed' = Closed
  String? _filterStatus = 'open';

  Stream<List<Map<String, dynamic>>> get _stream =>
      ProjectRepository().listProjectsStream(widget.userId, status: _filterStatus);

  Future<void> _openCreate() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateProjectScreen(),
        fullscreenDialog: true,
      ),
    );
    if (result == true) {
      setState(() {}); // refresh stream
    }
  }

  Future<void> _openEdit(Map<String, dynamic> project) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateProjectScreen(
          projectId: project['id'] as String,
          initialData: project,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == true) setState(() {});
  }

  Future<void> _confirmClose(Map<String, dynamic> project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Project?'),
        content: Text(
            'Mark "${project['name']}" as closed? You can reopen it later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Close Project')),
        ],
      ),
    );
    if (confirmed == true) {
      await ProjectRepository()
          .closeProject(widget.userId, project['id'] as String);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text(
            'This will permanently delete "${project['name']}". Reports are not deleted.'),
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
    if (confirmed == true) {
      await ProjectRepository()
          .deleteProject(widget.userId, project['id'] as String);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: 'open',   label: Text('Open')),
                ButtonSegment(value: 'closed', label: Text('Closed')),
                ButtonSegment(value: null,     label: Text('All')),
              ],
              selected: {_filterStatus},
              onSelectionChanged: (s) =>
                  setState(() => _filterStatus = s.first),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final projects = snap.data ?? [];
          if (projects.isEmpty) {
            return _EmptyState(
              filterStatus: _filterStatus,
              onCreateTap: _openCreate,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: projects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _ProjectCard(
              project: projects[i],
              onTap: () => Navigator.pushNamed(
                context,
                Paths.projectDetail,
                arguments: {
                  'projectId': projects[i]['id'] as String,
                  'project':   projects[i],
                },
              ),
              onEdit:   () => _openEdit(projects[i]),
              onClose:  projects[i]['status'] == 'open'
                  ? () => _confirmClose(projects[i])
                  : null,
              onDelete: () => _confirmDelete(projects[i]),
            ),
          );
        },
      ),
    );
  }
}

/* ─────────────────────────── Project card ─────────────────────────────── */

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onEdit,
    this.onClose,
    required this.onDelete,
  });

  final Map<String, dynamic> project;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onClose;
  final VoidCallback onDelete;

  static const _typeLabels = {
    'pipeline':        'Pipeline',
    'structural':      'Structural',
    'pressure_vessel': 'Pressure Vessel',
    'offshore':        'Offshore',
    'other':           'Other',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final name       = project['name']       as String? ?? 'Untitled';
    final client     = project['clientName'] as String? ?? '';
    final location   = project['location']   as String? ?? '';
    final type       = project['type']       as String? ?? 'other';
    final status     = project['status']     as String? ?? 'open';
    final startDate  = project['startDate']  as String? ?? '';
    final reportCount = project['reportCount'] as int? ?? 0;
    final isOpen     = status == 'open';

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: name + status + overflow menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  _StatusChip(isOpen: isOpen),
                  const SizedBox(width: 4),
                  PopupMenuButton<_Action>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (a) {
                      switch (a) {
                        case _Action.edit:   onEdit();
                        case _Action.close:  onClose?.call();
                        case _Action.delete: onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: _Action.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      if (onClose != null)
                        const PopupMenuItem(
                          value: _Action.close,
                          child: ListTile(
                            leading: Icon(Icons.lock_outlined),
                            title: Text('Close Project'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      PopupMenuItem(
                        value: _Action.delete,
                        child: ListTile(
                          leading: const Icon(Icons.delete_outlined,
                              color: Colors.red),
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

              if (client.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.business_outlined, size: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(client,
                      style: TextStyle(fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[600])),
                ]),
              ],

              if (location.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.location_on_outlined, size: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(location,
                      style: TextStyle(fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[600])),
                ]),
              ],

              const SizedBox(height: 10),

              // Footer row: type chip + date + report count
              Row(
                children: [
                  _TypeChip(label: _typeLabels[type] ?? 'Other'),
                  const Spacer(),
                  if (startDate.isNotEmpty)
                    Text(startDate,
                        style: TextStyle(fontSize: 12,
                            color: isDark ? Colors.grey[500] : Colors.grey[600])),
                  const SizedBox(width: 12),
                  Icon(Icons.description_outlined, size: 14,
                      color: scheme.primary),
                  const SizedBox(width: 2),
                  Text('$reportCount',
                      style: TextStyle(fontSize: 13,
                          color: scheme.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Action { edit, close, delete }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOpen ? Colors.green : Colors.grey,
          width: 1,
        ),
      ),
      child: Text(
        isOpen ? 'Open' : 'Closed',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isOpen ? Colors.green[700] : Colors.grey[600],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: scheme.onPrimaryContainer),
      ),
    );
  }
}

/* ─────────────────────────── Empty state ──────────────────────────────── */

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filterStatus, required this.onCreateTap});
  final String? filterStatus;
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    final isFiltered = filterStatus != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              isFiltered
                  ? 'No ${filterStatus == 'open' ? 'open' : 'closed'} projects'
                  : 'No projects yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Switch filters or create a new project.'
                  : 'Create your first project to organise reports by job site, client, and type.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add),
              label: const Text('New Project'),
            ),
          ],
        ),
      ),
    );
  }
}
