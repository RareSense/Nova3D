import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/features/chat/data/chat_service.dart';
import 'package:nova3d_frontend/features/chat/data/conversation_local_source.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

class ConversationRepository {
  ConversationRepository(this._local, this._remote);

  final ConversationLocalSource _local;
  final ChatService _remote;
  final Map<String, Timer> _snapshotDebounce = {};

  Future<List<ConversationModel>> load() => _local.loadConversations();

  Future<List<ConversationModel>> syncLatest({int limit = 50}) async {
    final remote = await _remote.getConversations(limit: limit);
    final local = await _local.loadConversations();
    final merged = _mergeConversations(local, remote);
    await _local.save(merged);
    return merged;
  }

  Future<ConversationModel> create(String title) async {
    final conv = await _remote.createConversation(title);
    final current = await _local.loadConversations();
    await _local.save(_mergeConversations([conv, ...current], const []));
    return conv;
  }

  Future<void> persist(List<ConversationModel> convs) => _local.save(convs);

  Future<List<MessageModel>> loadRemoteSnapshot(String conversationId) =>
      _remote.getSnapshotMessages(conversationId);

  Future<void> persistMessagesSnapshot({
    required ConversationModel conversation,
    required List<MessageModel> messages,
    bool immediate = false,
  }) async {
    if (messages.isEmpty) return;
    _snapshotDebounce.remove(conversation.id)?.cancel();

    Future<void> save() async {
      try {
        final updated = await _remote.updateConversationSnapshot(
          conversation.id,
          title: conversation.title,
          messages: messages,
        );
        final current = await _local.loadConversations();
        await _local.save(_mergeConversations(current, [updated]));
      } catch (e, st) {
        debugPrint(
          '[ConversationRepository] snapshot sync(${conversation.id}) failed: $e\n$st',
        );
      }
    }

    if (immediate) {
      await save();
      return;
    }

    _snapshotDebounce[conversation.id] = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(save()),
    );
  }

  Future<void> delete(String id) async {
    // Best-effort remote delete — a 404 or network error is non-fatal since
    // the conversation is already removed from the local list.
    try {
      await _remote.deleteConversation(id);
    } catch (e, st) {
      debugPrint('[ConversationRepository] remote delete($id) failed: $e\n$st');
    }
    await _local.deleteMessages(id);
  }

  List<ConversationModel> _mergeConversations(
    List<ConversationModel> local,
    List<ConversationModel> remote,
  ) {
    final byId = <String, ConversationModel>{};
    for (final conv in [...local, ...remote]) {
      final existing = byId[conv.id];
      if (existing == null || conv.updatedAt.isAfter(existing.updatedAt)) {
        byId[conv.id] = conv;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged;
  }
}
