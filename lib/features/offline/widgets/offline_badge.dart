// lib/features/offline/widgets/offline_badge.dart
//
// Small dot + label showing current online/offline status.
// Designed to fit inline in AppBars, DrawerHeaders, or status rows.

import 'package:flutter/material.dart';

class OfflineBadge extends StatelessWidget {
  const OfflineBadge({
    super.key,
    required this.isOnline,
    this.size = 12,
  });

  final bool isOnline;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? Colors.green : Colors.orange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          isOnline ? 'Online' : 'Offline',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
