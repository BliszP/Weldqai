// lib/features/offline/offline_mode_screen.dart
//
// Offline mode management screen.
// Shows connectivity status, last sync timestamp, and a Sync Now button
// that calls SyncService.syncForCurrentUser().

import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weldqai_app/core/providers/connectivity_provider.dart';
import 'package:weldqai_app/core/services/sync_service.dart';
import 'package:weldqai_app/core/services/logger_service.dart';
import 'package:weldqai_app/core/services/error_service.dart';
import 'package:weldqai_app/features/offline/widgets/sync_banner.dart';

class OfflineModeScreen extends ConsumerStatefulWidget {
  const OfflineModeScreen({super.key});

  @override
  ConsumerState<OfflineModeScreen> createState() => _OfflineModeScreenState();
}

class _OfflineModeScreenState extends ConsumerState<OfflineModeScreen> {
  bool _syncing = false;
  String? _lastSyncedAt;
  bool _offlineEnabled = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final sync = SyncService();
    final lastSync = await sync.lastSyncedAt();
    final enabled = await sync.offlineEnabled();
    if (!mounted) return;
    setState(() {
      _lastSyncedAt = lastSync;
      _offlineEnabled = enabled;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final count = await SyncService().syncForCurrentUser();
      final lastSync = await SyncService().lastSyncedAt();
      if (!mounted) return;
      setState(() {
        _lastSyncedAt = lastSync;
        _syncing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced $count items')),
      );
    } catch (e, st) {
      AppLogger.error('❌ Offline screen sync failed', error: e, stackTrace: st);
      await ErrorService.captureException(e, stackTrace: st, context: 'OfflineModeScreen._syncNow');
      if (!mounted) return;
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleOffline(bool enabled) async {
    await SyncService().enableOffline(enabled);
    if (!mounted) return;
    setState(() => _offlineEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final connectivityAsync = ref.watch(connectivityProvider);
    final isOnline = connectivityAsync.valueOrNull ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('Offline Mode')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connectivity banner
          SyncBanner(
            isOnline: isOnline,
            pendingCount: 0,
            onTapSync: isOnline && !_syncing ? _syncNow : null,
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- Status card ------------------------------------------
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sync Status',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _StatusRow(
                          icon: isOnline ? Icons.wifi : Icons.wifi_off,
                          color: isOnline ? Colors.green : Colors.orange,
                          label: isOnline ? 'Connected' : 'No connection',
                        ),
                        const SizedBox(height: 8),
                        _StatusRow(
                          icon: Icons.schedule,
                          color: Colors.grey,
                          label: _lastSyncedAt != null
                              ? 'Last synced: ${_formatTimestamp(_lastSyncedAt!)}'
                              : 'Never synced',
                        ),
                        const SizedBox(height: 8),
                        _StatusRow(
                          icon: _offlineEnabled
                              ? Icons.offline_bolt
                              : Icons.offline_bolt_outlined,
                          color: _offlineEnabled ? Colors.blue : Colors.grey,
                          label: _offlineEnabled
                              ? 'Offline persistence enabled'
                              : 'Offline persistence disabled',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // --- Sync now button --------------------------------------
                FilledButton.icon(
                  onPressed: isOnline && !_syncing ? _syncNow : null,
                  icon: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_syncing ? 'Syncing…' : 'Sync Now'),
                ),

                const SizedBox(height: 24),

                // --- Settings card ----------------------------------------
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable offline access'),
                          subtitle: const Text(
                            'Cache reports and data locally for use without internet.',
                          ),
                          value: _offlineEnabled,
                          onChanged: _toggleOffline,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // --- Info card -------------------------------------------
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.info_outline, size: 18),
                          SizedBox(width: 8),
                          Text('How offline mode works',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                        SizedBox(height: 8),
                        Text(
                          'When offline mode is enabled, Firestore caches your data '
                          'locally. You can still view and edit reports without '
                          'internet access. Changes sync automatically when you '
                          'reconnect, or tap "Sync Now" to force an immediate sync.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.year}-${_p(local.month)}-${_p(local.day)} '
        '${_p(local.hour)}:${_p(local.minute)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
