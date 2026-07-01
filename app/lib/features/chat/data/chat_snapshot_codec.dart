import 'package:nova3d_frontend/shared/models/message_model.dart';

const String kNova3dChatSnapshotKey = 'nova3d_chat_snapshot';

/// Builds the conversation snapshot stored in `conversation_metadata`.
///
/// Reference images are intentionally excluded: this snapshot is returned
/// inline for every conversation in the list endpoint, so embedding base64
/// images here makes the list response grow unbounded. Image thumbnails are
/// recovered from the per-message content when a conversation is opened.
Map<String, dynamic> buildChatSnapshotMetadata(List<MessageModel> messages) => {
  kNova3dChatSnapshotKey: {
    'schema_version': 1,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'messages': messages
        .map((message) => message.toContentJson(includeImages: false))
        .toList(),
  },
};

List<MessageModel> parseChatSnapshotMessages(Map<String, dynamic>? metadata) {
  final snapshot = metadata?[kNova3dChatSnapshotKey];
  if (snapshot is! Map) return const [];
  final rawMessages = snapshot['messages'];
  if (rawMessages is! List) return const [];
  return rawMessages
      .whereType<Map>()
      .map(
        (entry) => MessageModel.fromLocalJson(
          entry.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .toList(growable: false);
}
