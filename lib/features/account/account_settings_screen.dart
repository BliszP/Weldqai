// ignore_for_file: unused_field

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:weldqai_app/core/services/theme_controller.dart';
import 'package:weldqai_app/core/services/sync_service.dart';
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
  bool _syncing = false;

  bool _darkMode = ThemeController.i.isDark;
  String _units = 'metric';
  String _language = 'en';

  String? _companyLogoUrl;
  String? _clientLogoUrl;

  bool _offline = true;
  String? _lastSync;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _sync = SyncService();

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

        _units = (prefs['units'] as String?) ?? _units;
        _language = (prefs['language'] as String?) ?? _language;
      }

      _offline = await _sync.offlineEnabled();
      _lastSync = await _sync.lastSyncedAt();
    } catch (_) {
      // Keep defaults on error
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncNow() async {
    if (_uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not signed in')),
        );
      }
      return;
    }

    setState(() => _syncing = true);
    try {
      final count = await _sync.syncForCurrentUser();
      final last = await _sync.lastSyncedAt();
      
      if (mounted) {
        setState(() => _lastSync = last);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Synced $count items for offline use'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
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
        'companyLogoUrl': _companyLogoUrl,
        'clientLogoUrl': _clientLogoUrl, 
        'prefs': {
          'darkMode': _darkMode,
          'units': _units,
          'language': _language,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _sync.enableOffline(_offline);

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

  void _openUpgradeDialog() {
    showUpgradeOptionsDialog(context);
  }

  Widget _profileGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const minField = 180.0;
        final avail = constraints.maxWidth;
        final cols = math.max(1, ((avail + gap) / (minField + gap)).floor());
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

  Widget _buildSyncSubtitle() {
    if (_lastSync == null) {
      return const Text('Never synced - Tap to sync for offline use');
    }
    
    try {
      final date = DateTime.parse(_lastSync!);
      final diff = DateTime.now().difference(date);
      
      String timeAgo;
      if (diff.inMinutes < 1) {
        timeAgo = 'Just now';
      } else if (diff.inHours < 1) {
        timeAgo = '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
      } else if (diff.inDays < 1) {
        timeAgo = '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
      } else if (diff.inDays < 7) {
        timeAgo = '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
      } else {
        timeAgo = 'Over a week ago';
      }
      
      return Text('Last synced: $timeAgo');
    } catch (_) {
      return Text('Last synced: $_lastSync');
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle(context, 'Profile'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _profileGrid(),
                ),
              ),

              const SizedBox(height: 16),
              _sectionTitle(context, 'Branding'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
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
              ),

              const SizedBox(height: 16),
              _sectionTitle(context, 'Preferences'),
              Card(
                child: SwitchListTile.adaptive(
                  value: _darkMode,
                  onChanged: (v) {
                    setState(() => _darkMode = v);
                    ThemeController.i.setDark(v);
                  },
                  title: const Text('Dark Mode'),
                ),
              ),
              Card(
                child: ListTile(
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
              ),

              const SizedBox(height: 16),
              _sectionTitle(context, 'Offline & Sync'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: _offline,
                      onChanged: (v) => setState(() => _offline = v),
                      title: const Text('Offline Mode'),
                      subtitle: const Text('Cache data locally and queue changes when offline'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.sync),
                      title: const Text('Sync Now'),
                      subtitle: _buildSyncSubtitle(),
                      trailing: _syncing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _syncing ? null : _syncNow,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.grey),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Syncing downloads your reports, templates, and dashboard data for offline access',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _sectionTitle(context, 'Subscription'),
              ref.watch(subscriptionStatusProvider).when(
                loading: () => const Card(
                  child: ListTile(
                    leading: Icon(Icons.workspace_premium),
                    title: Text('Loading...'),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (status) {
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

                  return Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(icon, color: iconColor),
                          title: Text(title),
                          subtitle: Text(subtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _openUpgradeDialog,
                        ),
                        if (status.type == SubscriptionType.monthlyIndividual) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(12),
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
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),
              _sectionTitle(context, 'Security'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change Password'),
                  onTap: () => showChangePasswordSheet(context),
                ),
              ),

              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
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
                ],
              ),
              const SizedBox(height: 12),
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
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: body,
    );
  }

  Widget _sectionTitle(BuildContext ctx, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: Theme.of(ctx).textTheme.titleLarge),
      );

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