import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _role = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _certs = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    // prefill what we can
    _name.text = u?.displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _role.dispose();
    _phone.dispose();
    _address.dispose();
    _certs.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      // update FirebaseAuth displayName for convenience
      if (_name.text.trim().isNotEmpty) {
        await user.updateDisplayName(_name.text.trim());
      }

      final db = FirebaseFirestore.instance;
      await db.collection('users').doc(user.uid).set({
        'name': _name.text.trim(),
        'email': user.email,
        'company': _company.text.trim(),
        'role': _role.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'certifications': _certs.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'prefs': {
          'darkMode': false,
          'units': 'metric',
          'language': 'en',
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context, true); // return to previous (Auth or caller)
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
    return Scaffold(
      appBar: AppBar(title: const Text('Complete your profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('We’ll use this in projects, chat, reports & approvals.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),

              _Field(label: 'Full name', controller: _name, required: true),
              const SizedBox(height: 12),
              _ReadOnly(label: 'Email', value: email),
              const SizedBox(height: 12),
              _Field(label: 'Company', controller: _company),
              const SizedBox(height: 12),
              _Field(label: 'Role', controller: _role),
              const SizedBox(height: 12),
              _Field(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _Field(label: 'Address', controller: _address, maxLines: 2),
              const SizedBox(height: 12),
              _Field(label: 'Certifications', controller: _certs, maxLines: 2),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: (v) => (required && (v == null || v.trim().isEmpty)) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
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
