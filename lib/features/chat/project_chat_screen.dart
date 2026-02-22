// ignore_for_file: unused_element_parameter

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:weldqai_app/core/models/chat_message.dart';
import 'package:weldqai_app/core/repositories/chat_repository.dart';
import 'package:provider/provider.dart';
import 'package:weldqai_app/core/providers/workspace_provider.dart';
import 'package:weldqai_app/core/services/logger_service.dart';

/// NOTE: migrated to userId-scoped chat.
/// Kept class name for routing compatibility.
class ProjectChatScreen extends StatefulWidget {
  ProjectChatScreen({
    super.key,
    required this.userId, // <<--- was projectId
    String? channelId,
    ChatRepository? repository,
    String? senderId,
    String? senderName,
  })  : channelId = channelId ?? 'general',
        repository = repository ?? ChatRepository(),
        senderId =
            senderId ?? (FirebaseAuth.instance.currentUser?.uid ?? 'user-unknown'),
        senderName =
            senderName ?? (FirebaseAuth.instance.currentUser?.displayName ?? 'User');

  /// Root owner for the chat (previously projectId)
  final String userId;
  final String channelId; // defaults to 'general'
  final ChatRepository repository;
  final String senderId;   // current user id
  final String senderName; // current user display name

  @override
  State<ProjectChatScreen> createState() => _ProjectChatScreenState();
}

class _ProjectChatScreenState extends State<ProjectChatScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _dateFmt    = DateFormat('MMM d, HH:mm');

  // ----- mention picker (overlay anchored to composer) -----
  final LayerLink _mentionLink = LayerLink();
  OverlayEntry? _mentionOverlay;
  List<String> _knownSenders   = <String>[];
  List<String> _mentionResults = <String>[];

  // keep a small cache to build _knownSenders
  StreamSubscription<List<ChatMessage>>? _cacheSub;

  // typing indicator debounce
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();

    _cacheSub = widget.repository
        .streamMessages(widget.userId, widget.channelId)
        .listen((list) {
      // Build known senders set for @ mention suggestions
      final set = <String>{};
      for (final m in list) {
        if (m.senderName.isNotEmpty) set.add(m.senderName);
      }
      setState(() => _knownSenders = set.toList()..sort());

      // auto-scroll to bottom when new messages arrive
      _jumpToBottomSoon();
    });

    _inputCtrl.addListener(_onComposerChanged);
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    _typingDebounce?.cancel();
    _removeMentionOverlay();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---------- composer / mentions ----------
  void _onComposerChanged() {
    final text = _inputCtrl.text;
    final sel  = _inputCtrl.selection.baseOffset;
    if (sel <= 0 || sel > text.length) {
      _removeMentionOverlay();
    } else {
      final left = text.substring(0, sel);
      final m = RegExp(r'@([^\s@]{1,32})$').firstMatch(left);
      if (m == null) {
        _removeMentionOverlay();
      } else {
        final q = m.group(1)!.toLowerCase();
        final results = _knownSenders
            .where((n) => n.toLowerCase().contains(q))
            .take(6)
            .toList();
        if (results.isEmpty) {
          _removeMentionOverlay();
        } else {
          _mentionResults = results;
          _showMentionOverlay();
        }
      }
    }

    // simple typing indicator
    _typingDebounce?.cancel();
    widget.repository.setTyping(
      userId: widget.userId,
      channelId: widget.channelId,
      typingUserId: widget.senderId,
      isTyping: true,
    );
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      widget.repository.setTyping(
        userId: widget.userId,
        channelId: widget.channelId,
        typingUserId: widget.senderId,
        isTyping: false,
      );
    });
  }

  void _insertMention(String name) {
    final text = _inputCtrl.text;
    final sel  = _inputCtrl.selection.baseOffset;
    if (sel <= 0) return;

    final left = text.substring(0, sel);
    final right = text.substring(sel);
    final m = RegExp(r'@([^\s@]{1,32})$').firstMatch(left);
    if (m == null) return;

    final start = m.start;
    final newText = '${left.substring(0, start)}@$name $right';
    _inputCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: (start + name.length + 2)),
    );
    _removeMentionOverlay();
  }

  void _showMentionOverlay() {
    if (_mentionOverlay == null) {
      _mentionOverlay = OverlayEntry(
        builder: (context) => Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: Stack(
              children: [
                Positioned.fill(child: GestureDetector(onTap: _removeMentionOverlay)),
                CompositedTransformFollower(
                  link: _mentionLink,
                  offset: const Offset(0, -220),
                  showWhenUnlinked: false,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 200),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _mentionResults.length,
                        itemBuilder: (_, i) {
                          final n = _mentionResults[i];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?')),
                            title: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _insertMention(n),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      Overlay.of(context).insert(_mentionOverlay!);
    } else {
      _mentionOverlay!.markNeedsBuild();
    }
  }

  void _removeMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
  }

  // ---------- send / attach ----------
  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final mentions = RegExp(r'@([^\s@]{1,32})')
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toList();

    await widget.repository.sendMessage(
      userId: widget.userId,
      channelId: widget.channelId,
      text: text,
      senderId: widget.senderId,
      senderName: widget.senderName,
      mentions: mentions,
    );

    // ✅ FIXED WITH DEBUG: Send notifications based on actual workspace ownership
    try {
      final recipientIds = <String>[];
      final currentUserId = widget.senderId;  // The person sending the message
      final workspaceOwnerId = widget.userId;  // The workspace we're in
      
      AppLogger.debug('🔔 ========== CHAT NOTIFICATION DEBUG ==========');
      AppLogger.debug('   📤 Sender: $currentUserId (${widget.senderName})');
      AppLogger.debug('   📂 Workspace: $workspaceOwnerId');
      AppLogger.debug('   💬 Message: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');
      
      // Get the workspace provider to check context
      if (!mounted) return;
      final workspaceProvider = Provider.of<WorkspaceProvider>(context, listen: false);
      final isInOwnWorkspace = workspaceProvider.isViewingOwnWorkspace;
      
      AppLogger.debug('   🏠 Is in own workspace: $isInOwnWorkspace');
      
      if (isInOwnWorkspace) {
        // Current user is the owner - notify all collaborators
        AppLogger.debug('   📋 CASE 1: Owner sending message');
        AppLogger.debug('   🔍 Looking for collaborators in /users/$currentUserId/sharedWith/');
        
        final collaboratorsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('sharedWith')
            .get();
        
        AppLogger.debug('   ✅ Found ${collaboratorsSnap.docs.length} collaborator documents');
        
        for (final doc in collaboratorsSnap.docs) {
          AppLogger.debug('   👤 Collaborator found: ${doc.id}');
          AppLogger.debug('      Data: ${doc.data()}');
          recipientIds.add(doc.id);
        }
      } else {
        // Current user is a collaborator - notify owner and other collaborators
        AppLogger.debug('   📋 CASE 2: Collaborator sending message');
        
        // 1. Notify workspace owner
        AppLogger.debug('   👑 Adding workspace owner: $workspaceOwnerId');
        recipientIds.add(workspaceOwnerId);
        
        // 2. Notify other collaborators
        AppLogger.debug('   🔍 Looking for other collaborators in /users/$workspaceOwnerId/sharedWith/');
        final collaboratorsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(workspaceOwnerId)
            .collection('sharedWith')
            .get();
        
        AppLogger.debug('   ✅ Found ${collaboratorsSnap.docs.length} total collaborators');
        
        for (final doc in collaboratorsSnap.docs) {
          final collaboratorId = doc.id;
          if (collaboratorId != currentUserId) {
            AppLogger.debug('   👤 Adding other collaborator: $collaboratorId');
            recipientIds.add(collaboratorId);
          } else {
            AppLogger.debug('   ⏭️  Skipping self: $collaboratorId');
          }
        }
      }
      
      AppLogger.debug('   📬 Total recipients: ${recipientIds.length}');
      AppLogger.debug('   📬 Recipient IDs: $recipientIds');
      
      // Send notification to each recipient
      final messagePreview = text.length > 50 
          ? '${text.substring(0, 50)}...' 
          : text;
      
      for (final recipientId in recipientIds) {
        AppLogger.debug('   ✉️  Creating inbox document for: $recipientId');
        AppLogger.debug('      Path: /users/$recipientId/inbox/');
        
        final docRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(recipientId)
            .collection('inbox')
            .add({
          'title': 'New Chat Message',
          'body': '${widget.senderName}: $messagePreview',
          'type': 'chat',
          'channelId': widget.channelId,
          'workspaceOwnerId': workspaceOwnerId,
          'senderId': currentUserId,
          'senderName': widget.senderName,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        AppLogger.debug('   ✅ Inbox document created: ${docRef.id}');
      }
      
      AppLogger.debug('   🎉 All notifications sent successfully!');
      AppLogger.debug('🔔 ========== END DEBUG ==========');
    } catch (notifError, stackTrace) {
      AppLogger.error('❌ ========== NOTIFICATION ERROR ==========');
      AppLogger.debug('   Error: $notifError');
      AppLogger.debug('   Stack trace:');
      AppLogger.debug('   $stackTrace');
      AppLogger.error('❌ ========== END ERROR ==========');
    }

    _inputCtrl.clear();
    _removeMentionOverlay();
    _jumpToBottomSoon();
  }

  Future<void> _attach() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final name = f.name;
    final bytes = f.bytes ?? Uint8List(0);
    final mime = _guessMime(name);

    await widget.repository.sendAttachment(
      userId: widget.userId,
      channelId: widget.channelId,
      bytes: bytes,
      fileName: name,
      mimeType: mime,
      senderId: widget.senderId,
      senderName: widget.senderName,
    );
    _jumpToBottomSoon();
  }

  String _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  void _jumpToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _confirmDelete(BuildContext context, ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.deleteMessage(
        widget.userId,
        widget.channelId,
        message.id,
      );
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message deleted')),
        );
      }
    }
  }

  Future<void> _clearAllMessages(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Messages'),
        content: const Text(
          'This will permanently delete all messages in this channel. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.clearChannel(widget.userId, widget.channelId);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All messages cleared')),
        );
      }
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<WorkspaceProvider>(
          builder: (context, workspace, _) {
            final isOwnWorkspace = workspace.isViewingOwnWorkspace;
            
            if (isOwnWorkspace) {
              return Text('Chat — ${widget.channelId}');
            }
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Chat — ${widget.channelId}'),
                Text(
                  'Shared workspace',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
        actions: [
          Consumer<WorkspaceProvider>(
            builder: (context, workspace, _) {
              // Only show clear button if viewing own workspace
              if (workspace.isViewingOwnWorkspace) {
                return PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'clear') {
                      _clearAllMessages(context);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear all messages'),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: widget.repository.streamMessages(widget.userId, widget.channelId),
              builder: (context, snap) {
                final items = snap.data ?? const <ChatMessage>[];
                if (items.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final message = items[i];
                    return _MessageBubble(
                      me: widget.senderId,
                      m: message,
                      dateFmt: _dateFmt,
                      onDelete: () => _confirmDelete(context, message),
                    );
                  },
                );
              },
            ),
          ),

          // Composer row with @mention anchor and attach
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Attach',
                    icon: const Icon(Icons.attach_file),
                    onPressed: _attach,
                  ),
                  Expanded(
                    child: CompositedTransformTarget(
                      link: _mentionLink,
                      child: TextField(
                        controller: _inputCtrl,
                        decoration: InputDecoration(
                          hintText: 'Type a message…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: (_) => _send(),
                        minLines: 1,
                        maxLines: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Send',
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- message bubble ----------
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.me,
    required this.m,
    required this.dateFmt,
    this.onDelete,
  });

  final String me;
  final ChatMessage m;
  final DateFormat dateFmt;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isMe = m.senderId == me;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isMe
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget content() {
      if (m.isAttachment) {
        return InkWell(
          onTap: (m.fileUrl == null)
              ? null
              : () async {
                  final ok = await launchUrl(
                    Uri.parse(m.fileUrl!),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open attachment')),
                    );
                  }
                },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  m.fileName ?? 'attachment',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }
      return Text(m.text);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        // Long press to delete your own message
        onLongPress: isMe ? onDelete : null,
        child: Column(
          crossAxisAlignment: align,
          children: [
            Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMe)
                  CircleAvatar(
                    radius: 12,
                    child: Text(
                      m.senderName.isNotEmpty ? m.senderName[0].toUpperCase() : '?',
                    ),
                  ),
                if (!isMe) const SizedBox(width: 8),
                Text(
                  m.senderName,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  dateFmt.format(m.sentAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 620),
              child: content(),
            ),
          ],
        ),
      ),
    );
  }
}