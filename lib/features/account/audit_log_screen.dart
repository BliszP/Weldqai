// lib/features/account/audit_log_screen.dart
//
// Immutable audit trail for the authenticated user.
// Reads from /users/{uid}/audit_log (Firestore rules: create = owner, update/delete = false).
// Entries are written by AuditLogService whenever a report, project, or
// template is created, updated, locked, deleted, or exported.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:weldqai_app/core/services/audit_log_service.dart';

// ── Local helpers ──────────────────────────────────────────────────────────

const _entityAll       = 'all';
const _entityReport    = 'report';
const _entityProject   = 'project';
const _entityTemplate  = 'template';

const _filterLabels = <String, String>{
  _entityAll:      'All',
  _entityReport:   'Reports',
  _entityProject:  'Projects',
  _entityTemplate: 'Templates',
};

// Action → (icon, background color)
(IconData, Color) _actionStyle(String action) => switch (action) {
  AuditLogService.actionCreate => (Icons.add_circle_outline, const Color(0xFF22C55E)),
  AuditLogService.actionUpdate => (Icons.edit_outlined,       const Color(0xFF3B82F6)),
  AuditLogService.actionLock   => (Icons.lock_outlined,       const Color(0xFF8B5CF6)),
  AuditLogService.actionDelete => (Icons.delete_outlined,     const Color(0xFFEF4444)),
  AuditLogService.actionExport => (Icons.download_outlined,   const Color(0xFFF59E0B)),
  _                            => (Icons.info_outline,         Colors.grey),
};

String _actionLabel(String action, String entityType) {
  final entity = switch (entityType) {
    _entityReport   => 'report',
    _entityProject  => 'project',
    _entityTemplate => 'template',
    _               => entityType,
  };
  return switch (action) {
    AuditLogService.actionCreate => 'Created $entity',
    AuditLogService.actionUpdate => 'Updated $entity',
    AuditLogService.actionLock   => 'Locked $entity',
    AuditLogService.actionDelete => 'Deleted $entity',
    AuditLogService.actionExport => 'Exported $entity',
    _                            => '$action $entity',
  };
}

String _timeAgo(Timestamp? ts) {
  if (ts == null) return '';
  final dt  = ts.toDate().toLocal();
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60)  return 'just now';
  if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
  if (diff.inHours < 24)    return '${diff.inHours}h ago';
  if (diff.inDays < 7)      return '${diff.inDays}d ago';
  return DateFormat('dd MMM yyyy').format(dt);
}

String _fullTimestamp(Timestamp? ts) {
  if (ts == null) return '';
  return DateFormat('dd MMM yyyy HH:mm').format(ts.toDate().toLocal());
}

String _subtitle(Map<String, dynamic> entry) {
  final meta     = (entry['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
  final schemaId = meta['schemaId']  as String? ?? '';
  final projectId = meta['projectId'] as String? ?? '';
  final format   = meta['format']    as String? ?? '';
  final parts    = <String>[
    if (schemaId.isNotEmpty)  schemaId.replaceAll('_', ' '),
    if (projectId.isNotEmpty) 'project: ${projectId.substring(0, projectId.length.clamp(0, 8))}…',
    if (format.isNotEmpty)    format.toUpperCase(),
  ];
  return parts.join('  ·  ');
}

// ── Screen ─────────────────────────────────────────────────────────────────

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key, required this.userId});
  final String userId;

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String _filterEntity = _entityAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final entityFilter = _filterEntity == _entityAll ? null : _filterEntity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'About audit log',
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Entity filter chips ───────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                for (final entry in _filterLabels.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: _filterEntity == entry.key,
                    onSelected: (_) =>
                        setState(() => _filterEntity = entry.key),
                  ),
              ],
            ),
          ),
          const Divider(height: 0),

          // ── Log list ─────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: AuditLogService().watchAuditLog(
                widget.userId,
                limit: 100,
                entityType: entityFilter,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load audit log.\n${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final entries = snap.data ?? [];

                if (entries.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_outlined,
                              size: 56, color: cs.outlineVariant),
                          const SizedBox(height: 12),
                          Text(
                            'No audit entries yet.\nActivity will appear here as you use the app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 0, indent: 72),
                  itemBuilder: (_, i) => _AuditTile(entry: entries[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('About the Audit Log'),
        content: const Text(
          'The audit log records every create, update, lock, delete, and export '
          'event on your reports, projects, and templates.\n\n'
          'Entries are write-once and cannot be modified or deleted — '
          'providing a tamper-evident trail for QA/QC compliance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// ── Audit entry tile ────────────────────────────────────────────────────────

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final action     = entry['action']?.toString()     ?? '';
    final entityType = entry['entityType']?.toString() ?? '';
    final actorEmail = entry['actorEmail']?.toString();
    final ts         = entry['timestamp'] as Timestamp?;
    final (icon, color) = _actionStyle(action);
    final label      = _actionLabel(action, entityType);
    final subtitle   = _subtitle(entry);
    final ago        = _timeAgo(ts);
    final cs         = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            ago,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          if (actorEmail != null && actorEmail.isNotEmpty)
            Text(
              actorEmail,
              style: TextStyle(
                fontSize: 11,
                color: cs.primary.withValues(alpha: 0.8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      onTap: ts == null
          ? null
          : () => _showDetail(context, entry, label, ts, color, icon),
    );
  }

  void _showDetail(
    BuildContext context,
    Map<String, dynamic> entry,
    String label,
    Timestamp ts,
    Color color,
    IconData icon,
  ) {
    final meta      = (entry['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
    final actorEmail = entry['actorEmail']?.toString() ?? 'Unknown';
    final entityId  = entry['entityId']?.toString() ?? '';

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow('Time',  _fullTimestamp(ts)),
            _DetailRow('By',    actorEmail),
            if (entityId.isNotEmpty)
              _DetailRow('Entity ID', entityId),
            for (final kv in meta.entries)
              if (kv.value != null && kv.value.toString().isNotEmpty)
                _DetailRow(kv.key, kv.value.toString()),
            const SizedBox(height: 8),
            const Text(
              'Audit entries are immutable and cannot be modified or deleted.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
