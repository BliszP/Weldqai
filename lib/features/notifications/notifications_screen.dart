// lib/features/notifications/notifications_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    final inboxQ = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('inbox');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            onPressed: () async {
              final db = FirebaseFirestore.instance;
              await db
                  .collection('users')
                  .doc(userId)
                  .collection('meta')
                  .doc('meta')
                  .set({'inboxUnread': 0}, SetOptions(merge: true));
            },
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearAllDialog(context, userId),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: inboxQ.snapshots(includeMetadataChanges: true),
        builder: (context, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = s.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, i) {
              final doc = docs[i];
              final m = doc.data();
              final title = (m['title'] ?? 'Notification').toString();
              final body = (m['body'] ?? m['subtitle'] ?? '').toString();

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) async {
                  // Delete from Firestore
                  await doc.reference.delete();

                  // Decrement unread counter
                  final metaRef = FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('meta')
                      .doc('meta');

                  await metaRef.update({
                    'inboxUnread': FieldValue.increment(-1),
                  });

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notification deleted')),
                    );
                  }
                },
                child: ListTile(
                  title: Text(title),
                  subtitle: body.isNotEmpty ? Text(body) : null,
                  leading: const Icon(Icons.notifications),
                  onTap: () {
                    // Optional: navigate based on type/schemaId/reportId
                    // final type = m['type'];
                    // final schemaId = m['schemaId'];
                    // final reportId = m['reportId'];
                    // Navigate to relevant screen based on these values
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Future<void> _showClearAllDialog(
    BuildContext context,
    String userId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text(
          'This will permanently delete all notifications.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final batch = FirebaseFirestore.instance.batch();

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('inbox')
          .get();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      // Reset unread counter
      final metaRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('meta')
          .doc('meta');

      await metaRef.set({'inboxUnread': 0}, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications cleared')),
        );
      }
    }
  }
}