// ignore_for_file: unused_field

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:weldqai_app/app/constants/paths.dart';
import 'package:weldqai_app/core/services/theme_controller.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weldqai_app/core/providers/subscription_providers.dart';
import 'package:weldqai_app/core/services/subscription_service.dart';
import 'package:weldqai_app/features/account/widgets/upgrade_options_dialog.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class _UploadResult {
  _UploadResult({required this.url, required this.bytes});
  final String url;
  final Uint8List bytes;
}

class BrandingRuntimeAssets {
  static final Map<String, Uint8List> _companyLogoByUser = <String, Uint8List>{};
  static final Map<String, Uint8List> _signatureByUser = <String, Uint8List>{};

  static void setCompanyLogoBytes(String uid, Uint8List bytes) {
    _companyLogoByUser[uid] = bytes;
  }

  static Uint8List? getCompanyLogoBytes(String uid) {
    return _companyLogoByUser[uid];
  }

  static void setSignatureBytes(String uid, Uint8List bytes) {
    _signatureByUser[uid] = bytes;
  }

  static Uint8List? getSignatureBytes(String uid) {
    return _signatureByUser[uid];
  }
}

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _certCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  bool _darkMode = ThemeController.i.isDark;
  String _units = 'metric';
  String _language = 'en';

  String? _companyLogoUrl;
  String? _clientLogoUrl;

  String? _certBody;
  final _certNumberCtrl = TextEditingController();
  final _certExpiryCtrl = TextEditingController();

  static const _certBodies = [
    'AWS', 'ASME', 'API', 'CSWIP', 'PCN', 'TWI', 'BGAS', 'AMPP', 'IIW',
  ];

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String? get _uid => _auth.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _companyCtrl.dispose();
    _roleCtrl.dispose();
    _certCtrl.dispose();
    _certNumberCtrl.dispose();
    _certExpiryCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      _emailCtrl.text = _auth.currentUser?.email ?? '';

      if (_uid != null) {
        final doc = await _db
            .collection('users')
            .doc(_uid)
            .collection('profile')
            .doc('info')
            .get();
        
        final data = doc.data() ?? <String, dynamic>{};
        final prefs = (data['prefs'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

        _nameCtrl.text = (data['name'] ?? '').toString();
        _companyCtrl.text = (data['company'] ?? '').toString();
        _roleCtrl.text = (data['role'] ?? '').toString();
        _certCtrl.text = (data['certifications'] ?? '').toString();
        _phoneCtrl.text = (data['phone'] ?? '').toString();
        _addressCtrl.text = (data['address'] ?? '').toString();

        _companyLogoUrl = (data['companyLogoUrl'] ?? '') as String?;
        _clientLogoUrl  = (data['clientLogoUrl']  ?? '') as String?;

        _certBody = data['certBody'] as String?;
        _certNumberCtrl.text = (data['certNumber'] ?? '').toString();
        _certExpiryCtrl.text = (data['certExpiry'] ?? '').toString();

        _units = (prefs['units'] as String?) ?? _units;
        _language = (prefs['language'] as String?) ?? _language;
      }

    } catch (_) {
      // Keep defaults on error
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAll() async {
    if (_uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not signed in')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('profile')
          .doc('info')
          .set({
        'name': _nameCtrl.text.trim(),
        'company': _companyCtrl.text.trim(),
        'role': _roleCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'certifications': _certCtrl.text.trim(),
        'certBody':       _certBody,
        'certNumber':     _certNumberCtrl.text.trim(),
        'certExpiry':     _certExpiryCtrl.text.trim().isEmpty
            ? null
            : _certExpiryCtrl.text.trim(),
        'companyLogoUrl': _companyLogoUrl,
        'clientLogoUrl': _clientLogoUrl, 
        'prefs': {
          'darkMode': _darkMode,
          'units': _units,
          'language': _language,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_UploadResult?> _uploadBrandingImage({required String storagePath}) async {
    final trace = FirebasePerformance.instance.newTrace('logo_upload');
    bool traceStopped = false;
   
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (picked == null) return null;

      final fileBytes = await picked.readAsBytes();

      await trace.start();
      final startTime = DateTime.now();
      
      try {
        trace.setMetric('file_size_bytes', fileBytes.length);
        trace.putAttribute('logo_type', storagePath.contains('company') ? 'company' : 'client');
      } catch (e) {
        AppLogger.debug('Trace metric error (ignored): $e');
      }

      final ref = FirebaseStorage.instance.ref(storagePath);
      await ref.putData(fileBytes, SettableMetadata(contentType: 'image/png'));
      final url = await ref.getDownloadURL();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      try {
        trace.setMetric('upload_duration_ms', duration.inMilliseconds);
        trace.setMetric('success', 1);
      } catch (e) {
        AppLogger.debug('Trace metric error (ignored): $e');
      }

      try {
        if (!traceStopped) {
          await trace.stop();
          traceStopped = true;
        }
      } catch (traceError) {
        AppLogger.debug('Trace stop error (ignored): $traceError');
      }

      return _UploadResult(url: url, bytes: fileBytes);
      
    } catch (e) {
      try {
        trace.setMetric('success', 0);
        if (!traceStopped) {
          await trace.stop();
          traceStopped = true;
        }
      } catch (traceError) {
        AppLogger.debug('Trace stop error (ignored): $traceError');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _pickClientLogo() async {
    if (_uid == null) return;
    final res = await _uploadBrandingImage(
      storagePath: 'branding/$_uid/client_logo.png',
    );
    if (res != null && mounted) {
      setState(() => _clientLogoUrl = res.url);
    }
  }

  Future<void> _removeClientLogo() async {
    final url = _clientLogoUrl;
    if (url == null || url.isEmpty) return;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
    if (_uid != null) {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('profile')
          .doc('info')
          .set({'clientLogoUrl': FieldValue.delete()}, SetOptions(merge: true));
    }
    if (mounted) setState(() => _clientLogoUrl = null);
  }

  Future<void> _pickCompanyLogo() async {
    if (_uid == null) return;
    final res = await _uploadBrandingImage(
      storagePath: 'branding/$_uid/company_logo.png',
    );
    if (res != null && mounted) {
      setState(() => _companyLogoUrl = res.url);
      BrandingRuntimeAssets.setCompanyLogoBytes(_uid!, res.bytes);
    }
  }

  Future<void> _removeCompanyLogo() async {
    final url = _companyLogoUrl;
    if (url == null || url.isEmpty) return;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
    if (_uid != null) {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('profile')
          .doc('info')
          .set({'companyLogoUrl': FieldValue.delete()}, SetOptions(merge: true));
    }
    if (mounted) setState(() => _companyLogoUrl = null);
  }

  Future<void> _previewUrl(String? url, {String title = 'Preview'}) async {
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image to preview')),
      );
      return;
    }

    String resolved = url;
    try {
      resolved = await FirebaseStorage.instance.refFromURL(url).getDownloadURL();
    } catch (_) {}

    final ok = await launchUrl(Uri.parse(resolved), mode: LaunchMode.externalApplication);
    if (ok) return;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Open image'),
        content: SelectableText(resolved, style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: resolved));
              messenger.showSnackBar(const SnackBar(content: Text('Link copied')));
            },
            child: const Text('Copy link'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
      setState(() {
        _certExpiryCtrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _openUpgradeDialog() {
    showUpgradeOptionsDialog(context);
  }

  Widget _profileGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const minField = 220.0;
        const maxCols = 3; // never more than 3 columns on any screen size
        final avail = constraints.maxWidth;
        final cols = math.max(
            1, math.min(maxCols, ((avail + gap) / (minField + gap)).floor()));
        final cellW = (avail - (cols - 1) * gap) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _Field(label: 'Name', controller: _nameCtrl, width: cellW),
            _Field(label: 'Email', controller: _emailCtrl, readOnly: true, width: cellW),
            _Field(label: 'Company', controller: _companyCtrl, width: cellW),
            _Field(label: 'Role', controller: _roleCtrl, width: cellW),
            _Field(label: 'Certifications', controller: _certCtrl, width: cellW),
            _Field(label: 'Phone', controller: _phoneCtrl, width: cellW),
            _Field(label: 'Address', controller: _addressCtrl, width: cellW),
          ],
        );
      },
    );
  }

  // ── Subscription content (no Card wrapper — lives inside ExpansionTile) ──────

  Widget _buildSubscriptionContent(SubscriptionStatus status) {
    String title;
    String subtitle;
    Color? iconColor;
    IconData icon;

    switch (status.type) {
      case SubscriptionType.trial:
        icon = Icons.hourglass_empty;
        iconColor = Colors.orange;
        title = 'Free Trial';
        subtitle = '${status.reportsRemaining} reports left • ${status.daysRemaining} days';
        break;
      case SubscriptionType.trialExpired:
        icon = Icons.block;
        iconColor = Colors.red;
        title = 'Trial Ended';
        subtitle = 'Upgrade to continue';
        break;
      case SubscriptionType.payPerReport:
        icon = Icons.receipt_long;
        iconColor = Colors.blue;
        title = 'Pay Per Report';
        subtitle = '${status.creditsRemaining} reports remaining';
        break;
      case SubscriptionType.monthlyIndividual:
        icon = Icons.workspace_premium;
        iconColor = Colors.green;
        title = 'Individual Plan';
        if (status.currentPeriodEnd != null) {
          final renewDate = status.currentPeriodEnd!;
          final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          final formattedDate = '${months[renewDate.month - 1]} ${renewDate.day}, ${renewDate.year}';
          subtitle = status.cancelAtPeriodEnd == true
              ? 'Access until $formattedDate'
              : 'Renews $formattedDate for \$50.00';
        } else {
          subtitle = 'Unlimited reports';
        }
        break;
      case SubscriptionType.team:
        icon = Icons.groups;
        iconColor = Colors.purple;
        title = 'Team Plan';
        subtitle = status.isTeamOwner == true ? 'Team Owner' : 'Team Member';
        break;
      default:
        icon = Icons.help_outline;
        iconColor = null;
        title = 'Unknown';
        subtitle = 'Tap to upgrade';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: iconColor),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openUpgradeDialog,
        ),
        if (status.type == SubscriptionType.monthlyIndividual) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: const Text('Manage Subscription'),
                    onPressed: () async {
                      try {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 16),
                                Text('Opening billing portal...'),
                              ],
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        final callable = FirebaseFunctions.instance
                            .httpsCallable('createBillingPortalSession');
                        final result = await callable.call();
                        final portalUrl = result.data['url'] as String;
                        await launchUrl(
                          Uri.parse(portalUrl),
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to open portal: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cancel anytime, update payment method, or view billing history',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [

          // ── Profile ─────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Profile',
            icon: Icons.person_outlined,
            initiallyExpanded: true,
            child: _profileGrid(),
          ),

          // ── My Certification ────────────────────────────────────────────
          _SettingsSection(
            title: 'My Certification (PDF stamp)',
            icon: Icons.badge_outlined,
            subtitle: _certBody != null
                ? '$_certBody · ${_certNumberCtrl.text.isEmpty ? 'no number' : _certNumberCtrl.text}'
                : 'Not set — tap to configure',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your personal CWI, CSWIP, PCN or equivalent. Printed on all PDF '
                  'exports from this account. To stamp a different inspector on a '
                  'specific report, add them under Team Inspectors.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _certBody,
                  decoration: const InputDecoration(
                    labelText: 'Certifying body',
                    border: OutlineInputBorder(),
                  ),
                  items: _certBodies
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setState(() => _certBody = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _certNumberCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Certificate number',
                    hintText: 'e.g. CWI-123456',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _certExpiryCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Expiry date',
                    hintText: 'yyyy-MM-dd',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today_outlined),
                      onPressed: _pickCertExpiry,
                    ),
                  ),
                  onTap: _pickCertExpiry,
                ),
              ],
            ),
          ),

          // ── Team Inspectors ─────────────────────────────────────────────
          _SettingsSection(
            title: 'Team Inspectors',
            icon: Icons.group_outlined,
            subtitle: 'Manage inspectors who work under this account',
            child: _TeamInspectorsSection(userId: widget.userId),
          ),

          // ── Branding ────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Branding',
            icon: Icons.image_outlined,
            subtitle: 'Company & client logos printed on PDF exports',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _logoPreview(_companyLogoUrl),
                  title: const Text('Company Logo'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Shown on exported reports'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _pickCompanyLogo,
                            icon: const Icon(Icons.upload),
                            label: Text(_companyLogoUrl == null ? 'Upload' : 'Change'),
                          ),
                          if (_companyLogoUrl != null)
                            TextButton.icon(
                              onPressed: _removeCompanyLogo,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove'),
                            ),
                          if (_companyLogoUrl != null)
                            TextButton.icon(
                              onPressed: () => _previewUrl(_companyLogoUrl, title: 'Company Logo'),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Preview'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _logoPreview(_clientLogoUrl),
                  title: const Text('Client Logo'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Shown on exported reports (right side)'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _pickClientLogo,
                            icon: const Icon(Icons.upload),
                            label: Text(_clientLogoUrl == null ? 'Upload' : 'Change'),
                          ),
                          if (_clientLogoUrl != null)
                            TextButton.icon(
                              onPressed: _removeClientLogo,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove'),
                            ),
                          if (_clientLogoUrl != null)
                            TextButton.icon(
                              onPressed: () => _previewUrl(_clientLogoUrl, title: 'Client Logo'),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Preview'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              ],
            ),
          ),

          // ── Preferences ─────────────────────────────────────────────────
          _SettingsSection(
            title: 'Preferences',
            icon: Icons.tune_outlined,
            subtitle: '${_darkMode ? 'Dark' : 'Light'} mode · '
                '${_units == 'metric' ? 'Metric (mm/°C)' : 'Imperial (in/°F)'}',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _darkMode,
                  onChanged: (v) {
                    setState(() => _darkMode = v);
                    ThemeController.i.setDark(v);
                  },
                  title: const Text('Dark Mode'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Units / Language'),
                  subtitle: Text(
                    '${_units == "metric" ? "mm / °C" : "inch / °F"} • ${_language.toUpperCase()}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final res = await showDialog<_UnitsLangResult>(
                      context: context,
                      builder: (_) => Dialog(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: _UnitsLangSheet(units: _units, language: _language),
                        ),
                      ),
                    );
                    if (res != null) {
                      setState(() {
                        _units = res.units;
                        _language = res.language;
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          // ── Offline & Sync (nav — no expand needed) ─────────────────────
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.offline_bolt),
              title: const Text('Offline & Sync',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Manage offline access and sync settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, Paths.offline),
            ),
          ),

          // ── Subscription ────────────────────────────────────────────────
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.workspace_premium),
              title: const Text('Subscription',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              initiallyExpanded: true,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ref.watch(subscriptionStatusProvider).when(
                  loading: () => const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.workspace_premium),
                    title: Text('Loading...'),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: _buildSubscriptionContent,
                ),
              ],
            ),
          ),

          // ── Security ────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Security',
            icon: Icons.lock_outline,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change Password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showChangePasswordSheet(context),
            ),
          ),

          // ── Actions ─────────────────────────────────────────────────────
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveAll,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save Settings'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                await _auth.signOut();
                if (!mounted) return;
                nav.pushReplacementNamed('/auth');
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoPreview(String? url) {
    if (url == null || url.isEmpty) {
      return const CircleAvatar(radius: 20, child: Icon(Icons.image_not_supported));
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.transparent,
      child: ClipOval(
        child: Image.network(
          url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
        ),
      ),
    );
  }
}

// ── _SettingsSection ──────────────────────────────────────────────────────────
// Collapsible Card+ExpansionTile used for every settings group.

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? subtitle;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              )
            : null,
        initiallyExpanded: initiallyExpanded,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [child],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.readOnly = false,
    this.width,
  });

  final String label;
  final TextEditingController controller;
  final bool readOnly;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      readOnly: readOnly,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ).copyWith(labelText: label),
    );

    return SizedBox(
      width: width ?? 280,
      child: field,
    );
  }
}

class _UnitsLangResult {
  _UnitsLangResult(this.units, this.language);
  final String units;
  final String language;
}

class _UnitsLangSheet extends StatefulWidget {
  const _UnitsLangSheet({required this.units, required this.language});

  final String units;
  final String language;

  @override
  State<_UnitsLangSheet> createState() => _UnitsLangSheetState();
}

class _UnitsLangSheetState extends State<_UnitsLangSheet> {
  late String _units = widget.units;
  late String _lang = widget.language;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _units,
                  decoration: const InputDecoration(labelText: 'Units'),
                  items: const [
                    DropdownMenuItem(value: 'metric', child: Text('Metric (mm / °C)')),
                    DropdownMenuItem(value: 'imperial', child: Text('Imperial (in / °F)')),
                  ],
                  onChanged: (v) => setState(() => _units = v ?? 'metric'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _lang,
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (v) => setState(() => _lang = v ?? 'en'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, _UnitsLangResult(_units, _lang));
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showChangePasswordSheet(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: const _ChangePasswordSheet(),
      ),
    ),
  );
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _hasPasswordProvider {
    final u = FirebaseAuth.instance.currentUser;
    final providers = u?.providerData.map((p) => p.providerId).toList() ?? const [];
    return providers.contains('password');
  }

  Future<void> _handleChange() async {
    setState(() => _err = null);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_hasPasswordProvider) {
      setState(() => _err = 'Your account uses a social login. Add Email/Password first.');
      return;
    }
    if (_new.text.trim().length < 8) {
      setState(() => _err = 'Password must be at least 8 characters.');
      return;
    }
    if (_new.text.trim() != _confirm.text.trim()) {
      setState(() => _err = 'New passwords do not match.');
      return;
    }

    setState(() => _busy = true);
    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: _current.text.trim(),
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_new.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated')),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _err = e.message ?? 'Change failed. Check your current password.');
    } catch (e) {
      setState(() => _err = 'Change failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, insets + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Change Password',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current password',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _new,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _handleChange,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Update Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team Inspectors Section
//
// Manages additional inspector profiles stored at:
//   /users/{uid}/inspector_profiles/{profileId}
//
// Each profile captures the name, certifying body, certificate number, and
// expiry date of an inspector who works under this account.  Profiles can
// be selected per-report so the correct cert is stamped on the PDF export.
// ─────────────────────────────────────────────────────────────────────────────

class _TeamInspectorsSection extends StatelessWidget {
  const _TeamInspectorsSection({required this.userId});
  final String userId;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('inspector_profiles');

  Future<void> _addProfile(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _InspectorProfileDialog(),
    );
    if (result == null) return;
    await _col.add({
      ...result,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteProfile(
      BuildContext context, String docId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Inspector?'),
        content: Text('Remove "$name" from Team Inspectors?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _col.doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _col.orderBy('createdAt').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add inspectors who work under this account. Their certification '
                  'can be stamped on reports they perform — separate from the account '
                  'owner\'s personal cert above.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),

                if (docs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No additional inspectors yet.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  )
                else
                  ...docs.map((doc) {
                    final d          = doc.data();
                    final name       = d['name']       as String? ?? '';
                    final certBody   = d['certBody']   as String? ?? '';
                    final certNumber = d['certNumber'] as String? ?? '';
                    final certExpiry = d['certExpiry'] as String? ?? '';
                    final certLabel  = [
                      if (certBody.isNotEmpty)   certBody,
                      if (certNumber.isNotEmpty) certNumber,
                      if (certExpiry.isNotEmpty) 'exp. $certExpiry',
                    ].join(' · ');

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: certLabel.isNotEmpty
                          ? Text(certLabel,
                              style: const TextStyle(fontSize: 12))
                          : null,
                      trailing: IconButton(
                        icon:
                            const Icon(Icons.delete_outlined, color: Colors.red),
                        tooltip: 'Remove inspector',
                        onPressed: () =>
                            _deleteProfile(context, doc.id, name),
                      ),
                    );
                  }),

                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => _addProfile(context),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Add Inspector'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Add-inspector dialog ───────────────────────────────────────────────────

class _InspectorProfileDialog extends StatefulWidget {
  const _InspectorProfileDialog();

  @override
  State<_InspectorProfileDialog> createState() =>
      _InspectorProfileDialogState();
}

class _InspectorProfileDialogState extends State<_InspectorProfileDialog> {
  static const _certBodies = [
    'AWS', 'ASME', 'API', 'CSWIP', 'PCN', 'TWI', 'BGAS', 'AMPP', 'IIW',
  ];

  final _nameCtrl       = TextEditingController();
  final _certNumberCtrl = TextEditingController();
  final _certExpiryCtrl = TextEditingController();
  String? _certBody;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _certNumberCtrl.dispose();
    _certExpiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2040),
    );
    if (picked != null && mounted) {
      setState(() {
        _certExpiryCtrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Inspector'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full name *',
                hintText: 'e.g. John Smith',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _certBody,
              decoration: const InputDecoration(
                labelText: 'Certifying body',
                border: OutlineInputBorder(),
              ),
              items: _certBodies
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (v) => setState(() => _certBody = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _certNumberCtrl,
              decoration: const InputDecoration(
                labelText: 'Certificate number',
                hintText: 'e.g. CWI-123456',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _certExpiryCtrl,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Expiry date',
                hintText: 'yyyy-MM-dd',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: _pickExpiry,
                ),
              ),
              onTap: _pickExpiry,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, {
              'name':       name,
              'certBody':   _certBody,
              'certNumber': _certNumberCtrl.text.trim(),
              'certExpiry': _certExpiryCtrl.text.trim().isEmpty
                  ? null
                  : _certExpiryCtrl.text.trim(),
            });
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}