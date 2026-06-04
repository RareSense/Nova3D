import 'package:nova3d_frontend/features/chat/data/message_local_source.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

class MessageRepository {
  const MessageRepository(this._local);

  final MessageLocalSource _local;

  Future<List<MessageModel>> load(String conversationId) =>
      _local.loadMessages(conversationId);

  Future<void> persist(String conversationId, List<MessageModel> messages) =>
      _local.save(conversationId, messages);
}
