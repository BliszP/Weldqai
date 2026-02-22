import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';


import '../../core/models/chat_message.dart';



class ChatRepository {
  ChatRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  // CHANGED: Path from /projects/{projectId}/channels/... to /users/{userId}/channels/...
  CollectionReference<Map<String, dynamic>> _msgCol(
    String userId,
    String channelId,
  ) =>
      _db
          .collection('users')
          .doc(userId)
          .collection('channels')
          .doc(channelId)
          .collection('messages');

  /// Live messages ordered by time (ascending)
  Stream<List<ChatMessage>> streamMessages(
    String userId, // CHANGED
    String channelId,
  ) {
    return _msgCol(userId, channelId)
        .orderBy('sentAt', descending: false)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => [
              for (final d in snap.docs) ChatMessage.fromDoc(d),
            ]);
  }

  /// Send plain text message
  Future<void> sendMessage({
    required String userId, // CHANGED
    required String channelId,
    required String senderId,
    required String senderName,
    required String text,
    List<String> mentions = const <String>[],
  }) async {
    final msg = ChatMessage(
      id: _db.collection('_ids').doc().id,
      projectId: userId, // CHANGED: Keep field name for compatibility with ChatMessage model
      channelId: channelId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      sentAt: DateTime.now(),
      mentions: mentions,
    );
    await _msgCol(userId, channelId).add(msg.toMap());
  }

  /// Send an attachment (upload to Storage, then create message row)
  Future<void> sendAttachment({
    required String userId, // CHANGED
    required String channelId,
    required String senderId,
    required String senderName,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final id = _db.collection('_ids').doc().id;
    // CHANGED: Storage path from projects/... to users/...
    final path = 'users/$userId/channels/$channelId/attachments/$id/$fileName';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: mimeType));
    final url = await ref.getDownloadURL();

    final msg = ChatMessage(
      id: id,
      projectId: userId, // CHANGED: Keep field name for compatibility
      channelId: channelId,
      senderId: senderId,
      senderName: senderName,
      text: fileName,
      sentAt: DateTime.now(),
      isAttachment: true,
      fileName: fileName,
      fileUrl: url,
      mimeType: mimeType,
    );
    await _msgCol(userId, channelId).add(msg.toMap());
  }

  /// Delete a specific message (only if you're the sender)
/// Delete a specific message (only if you're the sender)
Future<void> deleteMessage(
  String userId,
  String channelId,
  String messageId,
) async {
  await _db
      .collection('users')
      .doc(userId)
      .collection('channels')  // Your repo uses 'channels', not 'chat'
      .doc(channelId)
      .collection('messages')
      .doc(messageId)
      .delete();
}

/// Clear all messages in a channel (only owner can do this)
Future<void> clearChannel(String userId, String channelId) async {
  final batch = _db.batch();
  
  final messagesSnapshot = await _db
      .collection('users')
      .doc(userId)
      .collection('channels')  // Your repo uses 'channels', not 'chat'
      .doc(channelId)
      .collection('messages')
      .get();
  
  for (final doc in messagesSnapshot.docs) {
    batch.delete(doc.reference);
  }
  
  await batch.commit();
}
  /// Simple typing flag per user
  Future<void> setTyping({
    required String userId, // CHANGED
    required String channelId,
    required String typingUserId,
    required bool isTyping,
  }) async {
    // CHANGED: Path
    final ref = _db
        .collection('users')
        .doc(userId)
        .collection('channels')
        .doc(channelId)
        .collection('typing')
        .doc(typingUserId);
    await ref.set({
      'isTyping': isTyping,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream list of userIds currently typing (updated in last 10s)
  Stream<List<String>> typingUsersStream(
    String userId, // CHANGED
    String channelId,
  ) {
    // CHANGED: Path
    final ref = _db
        .collection('users')
        .doc(userId)
        .collection('channels')
        .doc(channelId)
        .collection('typing');

    return ref.snapshots().map((snap) {
      final out = <String>[];
      final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
      for (final d in snap.docs) {
        final data = d.data();
        final ts = data['updatedAt'];
        final active = (data['isTyping'] == true) &&
            (ts is Timestamp ? ts.toDate().isAfter(cutoff) : true);
        if (active) out.add(d.id);
      }
      return out;
    });
  }

  /// For Visualization: live message count
  Stream<int> messageCountStream(String userId, String channelId) { // CHANGED
    return _msgCol(userId, channelId).snapshots().map((s) => s.size);
  }
}