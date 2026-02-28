import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _name     = TextEditingController();
  final _company  = TextEditingController();
  final _role     = TextEditingController();
  final _phone    = TextEditingController();
  final _address  = TextEditingController();
  // Structured cert fields (replaces free-text _certs)
  final _certNumber = TextEditingController();
  final _certExpiry = TextEditingController(); // ISO date string yyyy-MM-dd

  String? _certBody; // selected from dropdown

  bool _saving = false;

  static const _certBodies = [
    'AWS',    // American Welding Society
    'ASME',   // American Society of Mechanical Engineers
    'API',    // American Petroleum Institute
    'CSWIP',  // Certification Scheme for Welding and Inspection Personnel
    'PCN',    // Personnel Certification in Non-Destructive Testing
    'TWI',    // The Welding Institute
    'BGAS',   // British Gas
    'AMPP',   // Association for Materials Protection and Performance (was NACE)
    'IIW',    // International Institute of Welding
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _name.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _role.dispose();
    _phone.dispose();
    _address.dispose();
    _certNumber.dispose();
    _certExpiry.dispose();
    super.dispose();
  }

  Future<void> _pickCertExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 365 * 3)),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
      helpText: 'Certificate expiry date',
    );
    if (picked != null && mounted) {
      _certExpiry.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      if (_name.text.trim().isNotEmpty) {
        await user.updateDisplayName(_name.text.trim());
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name':    _name.text.trim(),
        'email':   user.email,
        'company': _company.text.trim(),
        'role':    _role.text.trim(),
        'phone':   _phone.text.trim(),
        'address': _address.text.trim(),
        // Structured CWI / inspector cert
        'certNumber': _certNumber.text.trim(),
        'certBody':   _certBody,
        'certExpiry': _certExpiry.text.trim().isEmpty ? null : _certExpiry.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'prefs': {
          'darkMode': false,
          'units': 'metric',
          'language': 'en',
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Complete your profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'We\'ll use this in projects, chat, reports & approvals.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),

              // ── Personal ──────────────────────────────────────────────
              _SectionHeader('Personal'),
              const SizedBox(height: 12),
              _Field(label: 'Full name', controller: _name, required: true),
              const SizedBox(height: 12),
              _ReadOnly(label: 'Email', value: email),
              const SizedBox(height: 12),
              _Field(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _Field(label: 'Address', controller: _address, maxLines: 2),

              const SizedBox(height: 20),

              // ── Professional ─────────────────────────────────────────
              _SectionHeader('Professional'),
              const SizedBox(height: 12),
              _Field(label: 'Company', controller: _company),
              const SizedBox(height: 12),
              _Field(label: 'Role / title', controller: _role),

              const SizedBox(height: 20),

              // ── Certification ─────────────────────────────────────────
              _SectionHeader('Inspector Certification'),
              const SizedBox(height: 4),
              Text(
                'CWI, CSWIP, PCN or equivalent. Printed on PDF reports.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),

              // Cert body dropdown
              DropdownButtonFormField<String>(
                value: _certBody,
                decoration: const InputDecoration(
                  labelText: 'Certifying body',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _certBodies
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setState(() => _certBody = v),
              ),
              const SizedBox(height: 12),

              _Field(
                label: 'Certificate number',
                controller: _certNumber,
                hint: 'e.g. CWI-123456',
              ),
              const SizedBox(height: 12),

              // Expiry date picker
              TextFormField(
                controller: _certExpiry,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Expiry date',
                  hintText: 'yyyy-MM-dd',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(Icons.calendar_today_outlined,
                        size: 18, color: scheme.primary),
                    onPressed: _pickCertExpiry,
                    tooltip: 'Pick expiry date',
                  ),
                ),
                onTap: _pickCertExpiry,
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Save & continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: (v) =>
          (required && (v == null || v.trim().isEmpty)) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ).copyWith(labelText: label),
      child: Text(value.isEmpty ? '—' : value),
    );
  }
}
