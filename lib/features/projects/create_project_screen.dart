import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:weldqai_app/core/repositories/project_repository.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

/// Screen for creating a new project or editing an existing one.
///
/// Pass [projectId] + [initialData] to enter edit mode.
class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({
    super.key,
    this.projectId,
    this.initialData,
  });

  final String? projectId;
  final Map<String, dynamic>? initialData;

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _clientCtrl   = TextEditingController();
  final _locationCtrl = TextEditingController();

  String _type   = 'structural';
  String _status = 'open';
  DateTime _startDate = DateTime.now();
  bool _saving = false;

  bool get _isEdit => widget.projectId != null;

  static const _types = [
    ('pipeline',        'Pipeline'),
    ('structural',      'Structural'),
    ('pressure_vessel', 'Pressure Vessel'),
    ('offshore',        'Offshore'),
    ('other',           'Other'),
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d != null) {
      _nameCtrl.text     = d['name']       as String? ?? '';
      _clientCtrl.text   = d['clientName'] as String? ?? '';
      _locationCtrl.text = d['location']   as String? ?? '';
      _type   = d['type']   as String? ?? 'structural';
      _status = d['status'] as String? ?? 'open';
      final sd = d['startDate'] as String?;
      if (sd != null && sd.isNotEmpty) {
        _startDate = DateTime.tryParse(sd) ?? DateTime.now();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _clientCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      final repo = ProjectRepository();
      final data = {
        'name':       _nameCtrl.text.trim(),
        'clientName': _clientCtrl.text.trim(),
        'location':   _locationCtrl.text.trim(),
        'type':       _type,
        'status':     _status,
        'startDate':  _startDate.toIso8601String().substring(0, 10),
        'endDate':    _status == 'closed'
            ? DateTime.now().toIso8601String().substring(0, 10)
            : null,
      };

      if (_isEdit) {
        await repo.updateProject(userId, widget.projectId!, data);
      } else {
        await repo.createProject(userId, data);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      AppLogger.error('❌ Failed to save project', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save project: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Project' : 'New Project'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text('Save', style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.primary)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Project Name ──────────────────────────────────────────────
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Project Name *',
                hintText: 'e.g. Bridge Deck Phase 2',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Project name is required' : null,
            ),

            const SizedBox(height: 16),

            // ── Client / Company ──────────────────────────────────────────
            TextFormField(
              controller: _clientCtrl,
              decoration: const InputDecoration(
                labelText: 'Client / Company',
                hintText: 'e.g. Acme Construction',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              textCapitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 16),

            // ── Location ──────────────────────────────────────────────────
            TextFormField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'e.g. Houston, TX',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              textCapitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 16),

            // ── Project Type ──────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Project Type',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _types.map((t) => DropdownMenuItem(
                value: t.$1,
                child: Text(t.$2),
              )).toList(),
              onChanged: (v) { if (v != null) setState(() => _type = v); },
            ),

            const SizedBox(height: 16),

            // ── Start Date ────────────────────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Start Date'),
              subtitle: Text(
                '${_startDate.year}-'
                '${_startDate.month.toString().padLeft(2, '0')}-'
                '${_startDate.day.toString().padLeft(2, '0')}',
              ),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Change'),
              ),
            ),

            const Divider(height: 32),

            // ── Status ────────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.circle_outlined, size: 20),
                const SizedBox(width: 12),
                const Text('Status'),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'open',
                      label: Text('Open'),
                      icon: Icon(Icons.lock_open, size: 16),
                    ),
                    ButtonSegment(
                      value: 'closed',
                      label: Text('Closed'),
                      icon: Icon(Icons.lock, size: 16),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) setState(() => _status = s.first);
                  },
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ── Save button (mobile fallback) ──────────────────────────────
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(_isEdit ? 'Update Project' : 'Create Project'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
