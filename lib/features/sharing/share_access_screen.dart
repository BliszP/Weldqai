import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'package:weldqai_app/core/repositories/user_data_repository.dart';
import 'package:weldqai_app/core/providers/workspace_provider.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

class ShareAccessScreen extends StatelessWidget {
  const ShareAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: _ShareAccessScaffold(),
    );
  }
}

class _ShareAccessScaffold extends StatefulWidget {
  const _ShareAccessScaffold();

  @override
  State<_ShareAccessScaffold> createState() => _ShareAccessScaffoldState();
}

class _ShareAccessScaffoldState extends State<_ShareAccessScaffold> {
  final _repo = UserDataRepository();
  final _emailController = TextEditingController();
  bool _writeAccess = false;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
  final ownerId = _currentUid;
  final email = _emailController.text.trim();

  if (ownerId == null) {
    _snack('Please sign in.');
    return;
  }
  if (email.isEmpty || !_isValidEmail(email)) {
    _snack('Enter a valid email address.');
    return;
  }

  final perms = _writeAccess ? <String>['read', 'write'] : <String>['read'];
  try {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    await _repo.inviteByEmail(ownerId, email, permissions: perms);
    
    // ✅ NEW: Send notification to invitee
    try {
      // Get owner's name for notification
      final ownerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .collection('profile')
          .doc('info')
          .get();
      
      final ownerName = ownerDoc.data()?['name'] ?? 
                        ownerDoc.data()?['displayName'] ?? 
                        'Someone';
      
      // Get invitee's UID from directory
      final directoryQuery = await FirebaseFirestore.instance
          .collection('directory')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      if (directoryQuery.docs.isNotEmpty) {
        final inviteeUid = directoryQuery.docs.first.id;
        
        // Create inbox notification
        await FirebaseFirestore.instance
            .collection('users')
            .doc(inviteeUid)
            .collection('inbox')
            .add({
          'title': 'Workspace Invitation',
          'body': '$ownerName invited you to their workspace with ${perms.join(", ")} access',
          'type': 'workspace_invite',
          'workspaceOwnerId': ownerId,
          'permissions': perms,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (notifError) {
      // Don't fail the whole operation if notification fails
      AppLogger.debug('Failed to send notification: $notifError');
    }
    
    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      _emailController.clear();
      setState(() => _writeAccess = false);
      _snack('✅ Access granted to $email (${perms.join(", ")})');
    }
  } catch (e) {
    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      _snack('❌ Failed to share: $e');
    }
  }
}

  bool _isValidEmail(String email) {
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(email);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final uid = _currentUid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share & Access'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Invite'),
            Tab(text: 'My collaborators'),
            Tab(text: 'Shared with me'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _InviteByEmailTab(
            emailController: _emailController,
            writeAccess: _writeAccess,
            onToggleWrite: (v) => setState(() => _writeAccess = v),
            onInvite: _invite,
          ),
          if (uid == null)
            const _CenteredNote('Please sign in to view collaborators.')
          else
            _CollaboratorsList(repo: _repo, ownerId: uid),
          if (uid == null)
            const _CenteredNote('Please sign in to view items shared with you.')
          else
            _SharedWithMeList(repo: _repo, myUid: uid),
        ],
      ),
    );
  }
}

class _InviteByEmailTab extends StatelessWidget {
  const _InviteByEmailTab({
    required this.emailController,
    required this.writeAccess,
    required this.onToggleWrite,
    required this.onInvite,
  });

  final TextEditingController emailController;
  final bool writeAccess;
  final ValueChanged<bool> onToggleWrite;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Invite a collaborator by email',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'e.g. user@example.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Allow write access'),
          subtitle: const Text('If off, collaborator is read-only'),
          value: writeAccess,
          onChanged: onToggleWrite,
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.person_add),
          label: const Text('Share'),
          onPressed: onInvite,
        ),
        const SizedBox(height: 24),
        const Text(
          'Note',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sharing uses a /directory collection to resolve email → UID. '
          'Make sure users have logged in at least once so their directory record exists.',
        ),
      ],
    );
  }
}

class _CollaboratorsList extends StatelessWidget {
  const _CollaboratorsList({required this.repo, required this.ownerId});

  final UserDataRepository repo;
  final String ownerId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: repo.watchMyCollaborators(ownerId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snap.hasError) {
          return _CenteredNote('Error: ${snap.error}');
        }
        
        final docs = snap.data?.docs ?? const [];
        
        if (docs.isEmpty) {
          return const _CenteredNote('No collaborators yet.');
        }
        
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final collaboratorId = d['collaboratorId'] as String? ?? docs[i].id;
            
            // ✅ FIX: Read the email and display name from the document
            final collaboratorEmail = d['collaboratorEmail'] as String? ?? 'No email';
            final collaboratorDisplayName = d['collaboratorDisplayName'] as String? ?? collaboratorEmail;
            final permissions = (d['permissions'] as List?)?.join(', ') ?? 'read';
            
            return ListTile(
              leading: const Icon(Icons.person),
              // ✅ FIX: Display the name or email instead of UID
              title: Text(collaboratorDisplayName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (collaboratorEmail != collaboratorDisplayName)
                    Text(collaboratorEmail),
                  Text('Permissions: $permissions'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove access',
                onPressed: () async {
                  // Save the BuildContext before any async operations
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  // Confirm before removing
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Remove Access'),
                      content: Text('Remove access for $collaboratorDisplayName?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirmed == true) {
                    try {
                      await repo.removeSharedAccess(ownerId, collaboratorId);
                      // Use the saved ScaffoldMessenger instead of context
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('✅ Removed access for $collaboratorDisplayName'),
                        ),
                      );
                    } catch (e) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('❌ Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _SharedWithMeList extends StatelessWidget {
  const _SharedWithMeList({required this.repo, required this.myUid});

  final UserDataRepository repo;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: repo.watchSharedWithMe(myUid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snap.hasError) {
          return _CenteredNote('Error: ${snap.error}');
        }
        
        final docs = snap.data?.docs ?? const [];
        
        if (docs.isEmpty) {
          return const _CenteredNote('No workspaces shared with you.');
        }
        
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final ownerId = docs[i].id; // Document ID is the owner's UID
            final permissions = (d['permissions'] as List?)?.join(', ') ?? 'read';
            
            // ✅ FIX: Fetch owner's display name from their profile
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(ownerId)
                  .collection('profile')
                  .doc('info')
                  .get(),
              builder: (context, profileSnap) {
                String ownerDisplayName = ownerId; // Default to UID
                String? ownerEmail;
                
                if (profileSnap.hasData && profileSnap.data?.exists == true) {
                  final profileData = profileSnap.data!.data() as Map<String, dynamic>?;
                  ownerDisplayName = profileData?['displayName'] as String? ?? ownerId;
                  ownerEmail = profileData?['email'] as String?;
                }
                
                return ListTile(
                  leading: const Icon(Icons.folder_shared),
                  // ✅ FIX: Display owner's name instead of UID
                  title: Text(ownerDisplayName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ownerEmail != null && ownerEmail != ownerDisplayName)
                        Text(ownerEmail),
                      Text('Your permissions: $permissions'),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // Switch to the shared workspace
                    context.read<WorkspaceProvider>().switchToWorkspace(ownerId);
                    
                    // Show notification
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Switched to $ownerDisplayName\'s workspace'),
                      ),
                    );
                    
                    // Navigate to dashboard
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/dashboard',
                      (route) => false,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CenteredNote extends StatelessWidget {
  const _CenteredNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}