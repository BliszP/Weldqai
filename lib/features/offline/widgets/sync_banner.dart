// lib/features/offline/widgets/sync_banner.dart
//
// Slim 40-px banner showing connectivity state and a manual Sync button.
// Implements PreferredSizeWidget so it can be used as AppBar.bottom,
// but also renders correctly when placed in a Column.

import 'package:flutter/material.dart';

class SyncBanner extends StatelessWidget implements PreferredSizeWidget {
  const SyncBanner({
    super.key,
    required this.isOnline,
    required this.pendingCount,
    this.onTapSync,
  });

  final bool isOnline;
  final int pendingCount;
  final Future<void> Function()? onTapSync;

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context) {
    final hasPending = pendingCount > 0;
    final color = isOnline ? Colors.green : Colors.orange;
    final bgColor = isOnline
        ? Colors.green.withValues(alpha: 0.10)
        : Colors.orange.withValues(alpha: 0.10);

    String label;
    if (isOnline) {
      label = hasPending
          ? 'Online · $pendingCount pending — syncing shortly'
          : 'Online';
    } else {
      label = hasPending
          ? 'Offline · $pendingCount pending — will sync when connected'
          : 'Offline — changes will sync when connected';
    }

    return Container(
      height: preferredSize.height,
      color: bgColor,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(isOnline ? Icons.wifi : Icons.wifi_off, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasPending && onTapSync != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                try {
                  await onTapSync!.call();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sync failed: $e')),
                    );
                  }
                }
              },
              child: const Text('Sync'),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
