import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.projectId,
    required this.channelId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.isAttachment = false,
    this.fileName,
    this.fileUrl,
    this.mimeType,
    this.mentions = const <String>[],
  });

  final String id;
  final String projectId;
  final String channelId;
  final String senderId;
  final String senderName;
  final String text;              // message text or attachment caption
  final DateTime sentAt;          // when sent
  final bool isAttachment;        // true if this row represents a file
  final String? fileName;         // optional file name
  final String? fileUrl;          // optional download url
  final String? mimeType;         // optional MIME
  final List<String> mentions;    // @mentions (uids or names)

  Map<String, dynamic> toMap() => {
        'projectId': projectId,
        'channelId': channelId,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'sentAt': Timestamp.fromDate(sentAt),
        'isAttachment': isAttachment,
        'fileName': fileName,
        'fileUrl': fileUrl,
        'mimeType': mimeType,
        'mentions': mentions,
      };

  static ChatMessage fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ChatMessage(
      id: doc.id,
      projectId: (d['projectId'] ?? '') as String,
      channelId: (d['channelId'] ?? '') as String,
      senderId: (d['senderId'] ?? '') as String,
      senderName: (d['senderName'] ?? '') as String,
      text: (d['text'] ?? '') as String,
      sentAt: (d['sentAt'] is Timestamp)
          ? (d['sentAt'] as Timestamp).toDate()
          : DateTime.now(),
      isAttachment: (d['isAttachment'] ?? false) as bool,
      fileName: d['fileName'] as String?,
      fileUrl: d['fileUrl'] as String?,
      mimeType: d['mimeType'] as String?,
      mentions: (d['mentions'] is List)
          ? List<String>.from(d['mentions'] as List)
          : const <String>[],
    );
  }
}
