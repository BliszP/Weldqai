// lib/features/reports/reports_history_screen.dart
//
// Searchable, filterable list of all inspection reports for a user.
// Optionally scoped to a single project when [projectId] is provided.
// Uses collectionGroup('items') so results span every schema sub-collection.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/core/repositories/report_repository.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

// ── Workflow status helpers ────────────────────────────────────────────────

enum _WfStatus { draft, submitted, approved, rejected }

_WfStatus _parseWf(String? raw) => switch (raw) {
      'submitted' => _WfStatus.submitted,
      'approved'  => _WfStatus.approved,
      'rejected'  => _WfStatus.rejected,
      _           => _WfStatus.draft,
    };

Color _wfColor(_WfStatus s) => switch (s) {
      _WfStatus.draft     => Colors.grey,
      _WfStatus.submitted => Colors.blue,
      _WfStatus.approved  => Colors.green,
      _WfStatus.rejected  => Colors.red,
    };

String _wfLabel(_WfStatus s) => switch (s) {
      _WfStatus.draft     => 'Draft',
      _WfStatus.submitted => 'Submitted',
      _WfStatus.approved  => 'Approved',
      _WfStatus.rejected  => 'Rejected',
    };

// ── Schema labels ─────────────────────────────────────────────────────────

const _schemaLabels = <String, String>{
  'welding_operation':        'Welding',
  'structural_fillet':        'Structural/Fillet',
  'visual_inspection':        'Visual Inspection',
  'ndt_rt':                   'NDT (RT)',
  'ndt_ut':                   'NDT (UT)',
  'ndt_mpi':                  'NDT (MPI)',
  'hydrotest':                'Hydrotest',
  'coating_painting':         'Coating/Painting',
  'anode_installation':       'Anode Install',
  'pipe_tally_log':           'Pipe Tally',
  'wps_pqr_register':         'WPS/PQR',
  'welder_qualification_record': 'Welder Qual',
  'pwht_record':              'PWHT',
  'fit_up_inspection_report': 'Fit-Up Inspection',
  'custom_template_example':  'Custom Template',
};

String _schemaLabel(String? schemaId) {
  if (schemaId == null) return 'Unknown';
  return _schemaLabels[schemaId] ?? schemaId.replaceAll('_', ' ').split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

// ── Screen ────────────────────────────────────────────────────────────────

class ReportsHistoryScreen extends StatefulWidget {
  const ReportsHistoryScreen({
    super.key,
    required this.userId,
    this.projectId,
    this.projectName,
  });

  final String userId;
  final String? projectId;
  final String? projectName;

  @override
  State<ReportsHistoryScreen> createState() => _ReportsHistoryScreenState();
}

class _ReportsHistoryScreenState extends State<ReportsHistoryScreen> {
  final _repo = ReportRepository();
  final _searchCtrl = TextEditingController();

  bool _showSearch = false;
  String _searchQuery = '';
  _WfStatus? _filterStatus; // null = show all

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _summaryText(Map<String, dynamic> item) {
    final payload = (item['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    final details = (payload['details'] as Map?)?.cast<String, dynamic>() ?? {};

    // Try common header fields
    for (final key in [
      'job_no', 'jobNo', 'report_no', 'reportNo',
      'weld_no', 'weldNo', 'location', 'client',
    ]) {
      final v = details[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }

    // Fall back to updatedAtText
    final ts = item['updatedAtText']?.toString() ?? '';
    return ts.isNotEmpty ? 'Updated $ts' : '';
  }

  String _dateLabel(Map<String, dynamic> item) {
    final ts = item['updatedAt'];
    if (ts is Timestamp) {
      return DateFormat('dd MMM yyyy').format(ts.toDate().toLocal());
    }
    return item['updatedAtText']?.toString().substring(0, 10) ?? '';
  }

  bool _matches(Map<String, dynamic> item) {
    if (_filterStatus != null && _parseWf(item['workflowStatus']?.toString()) != _filterStatus) {
      return false;
    }
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final schema = _schemaLabel(item['schemaId']?.toString()).toLowerCase();
    final summary = _summaryText(item).toLowerCase();
    return schema.contains(q) || summary.contains(q);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _updateStatus(
    Map<String, dynamic> item,
    String newStatus, {
    String? note,
  }) async {
    final schemaId = item['schemaId']?.toString() ?? '';
    final reportId = item['id']?.toString() ?? '';
    if (schemaId.isEmpty || reportId.isEmpty) return;

    try {
      await _repo.updateWorkflowStatus(
        widget.userId, schemaId, reportId, newStatus,
        note: note,
      );
    } catch (e) {
      AppLogger.error('Failed to update workflow status', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _showRejectDialog(Map<String, dynamic> item) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Report'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (confirmed == true) {
      await _updateStatus(item, 'rejected', note: ctrl.text.trim());
    }
  }

  Future<void> _deleteDraft(Map<String, dynamic> item) async {
    final schemaId = item['schemaId']?.toString() ?? '';
    final reportId = item['id']?.toString() ?? '';
    if (schemaId.isEmpty || reportId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft?'),
        content: const Text(
            'This permanently deletes the draft report and cannot be undone.'),
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
    if (confirmed != true || !mounted) return;

    try {
      await _repo.deleteItem(
        userId: widget.userId,
        schemaId: schemaId,
        itemId: reportId,
      );
    } catch (e) {
      AppLogger.error('Failed to delete draft report', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  void _openReport(Map<String, dynamic> item) {
    final schemaId = item['schemaId']?.toString() ?? '';
    final reportId = item['id']?.toString() ?? '';
    if (schemaId.isEmpty || reportId.isEmpty) return;

    Navigator.pushNamed(
      context,
      Paths.dynamicReport,
      arguments: {
        'schemaId':    schemaId,
        'schemaTitle': _schemaLabel(schemaId),
        'docId':       reportId,
        if (item['projectId'] != null) 'projectId': item['projectId'],
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStr = widget.projectName != null
        ? '${widget.projectName} — History'
        : 'Inspection History';

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search inspections…',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              )
            : Text(titleStr),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            tooltip: _showSearch ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchCtrl.clear();
                _searchQuery = '';
              }
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter chips ──────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filterStatus == null,
                  onSelected: (_) => setState(() => _filterStatus = null),
                ),
                for (final s in _WfStatus.values)
                  FilterChip(
                    label: Text(_wfLabel(s)),
                    selected: _filterStatus == s,
                    selectedColor: _wfColor(s).withValues(alpha: 0.2),
                    checkmarkColor: _wfColor(s),
                    onSelected: (_) => setState(
                      () => _filterStatus = _filterStatus == s ? null : s,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 0),

          // ── List ──────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _repo.watchReportHistory(
                widget.userId,
                projectId: widget.projectId,
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
                        'Could not load history.\n${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final all = snap.data ?? [];
                final filtered = all.where(_matches).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_outlined,
                              size: 56, color: cs.outlineVariant),
                          const SizedBox(height: 12),
                          Text(
                            all.isEmpty
                                ? 'No inspections yet.\nStart one from the project page.'
                                : 'No results for current filter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 0, indent: 72),
                  itemBuilder: (_, i) => _ReportTile(
                    item: filtered[i],
                    onTap: () => _openReport(filtered[i]),
                    onSubmit: () => _updateStatus(filtered[i], 'submitted'),
                    onApprove: () => _updateStatus(filtered[i], 'approved'),
                    onReject: () => _showRejectDialog(filtered[i]),
                    onDelete: () => _deleteDraft(filtered[i]),
                    dateLabel: _dateLabel(filtered[i]),
                    summary: _summaryText(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Report tile ───────────────────────────────────────────────────────────

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.item,
    required this.onTap,
    required this.onSubmit,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
    required this.dateLabel,
    required this.summary,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onSubmit;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;
  final String dateLabel;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final schemaId = item['schemaId']?.toString() ?? '';
    final wf = _parseWf(item['workflowStatus']?.toString());
    final label = _schemaLabel(schemaId);
    final abbr = label.isNotEmpty ? label[0].toUpperCase() : '?';
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: _wfColor(wf).withValues(alpha: 0.15),
        child: Text(
          abbr,
          style: TextStyle(
            color: _wfColor(wf),
            fontWeight: FontWeight.bold,
          ),
        ),
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
          _WfChip(wf),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          [if (summary.isNotEmpty) summary, if (dateLabel.isNotEmpty) dateLabel]
              .join('  ·  '),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          switch (v) {
            case 'open':    onTap();
            case 'submit':  onSubmit();
            case 'approve': onApprove();
            case 'reject':  onReject();
            case 'delete':  onDelete();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'open', child: Text('Open / Edit')),
          if (wf == _WfStatus.draft) ...[
            const PopupMenuItem(value: 'submit', child: Text('Submit for Review')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete Draft',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
          if (wf == _WfStatus.submitted) ...[
            const PopupMenuItem(value: 'approve', child: Text('Approve')),
            const PopupMenuItem(value: 'reject',  child: Text('Reject')),
          ],
          if (wf == _WfStatus.rejected)
            const PopupMenuItem(value: 'submit', child: Text('Resubmit')),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _WfChip extends StatelessWidget {
  const _WfChip(this.status);
  final _WfStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _wfColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _wfLabel(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
