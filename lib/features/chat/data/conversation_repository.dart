import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/features/chat/data/chat_service.dart';
import 'package:nova3d_frontend/features/chat/data/chat_snapshot_codec.dart';
import 'package:nova3d_frontend/features/chat/data/conversation_local_source.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

class ConversationRepository {
  ConversationRepository(this._local, this._remote);

  final ConversationLocalSource _local;
  final ChatService _remote;
  final Map<String, Timer> _snapshotDebounce = {};
  final Set<String> _messagePersistKeys = {};

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

  /// Loads messages from the server. If [cachedMetadata] is provided (i.e. the
  /// conversation was already fetched as part of the list API), its embedded
  /// snapshot is used directly and the redundant GET /conversations/{id} call
  /// is skipped.
  Future<List<MessageModel>> loadRemoteMessages(
    String conversationId, {
    Map<String, dynamic>? cachedMetadata,
  }) async {
    final snapshotMessages = cachedMetadata != null
        ? parseChatSnapshotMessages(cachedMetadata)
        : await _remote.getSnapshotMessages(conversationId);
    final messages = await _remote.getMessages(conversationId);
    return _mergeMessages(messages, snapshotMessages);
  }

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
        await _persistStableMessages(conversation.id, messages);
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

  Future<void> _persistStableMessages(
    String conversationId,
    List<MessageModel> messages,
  ) async {
    for (final message in messages) {
      if (message.isStreaming) continue;
      final key = '$conversationId:${message.id}';
      if (_messagePersistKeys.contains(key)) continue;
      final receipt = await _remote.appendMessage(conversationId, message);
      final workflowId = message.workflowId;
      if (workflowId != null && workflowId.isNotEmpty) {
        await _remote.linkWorkflowToMessage(
          conversationId,
          workflowId: workflowId,
          remoteMessageId: receipt.id,
          operation: message.operation ?? 'generation',
        );
      }
      _messagePersistKeys.add(key);
    }
  }

  /// Cancels all pending snapshot debounce timers and clears the persist-once
  /// set. Must be called on logout so stale background writes don't fire after
  /// the session ends.
  void cancelPendingTimers() {
    for (final timer in _snapshotDebounce.values) {
      timer.cancel();
    }
    _snapshotDebounce.clear();
    _messagePersistKeys.clear();
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
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  List<MessageModel> _mergeMessages(
    List<MessageModel> primary,
    List<MessageModel> secondary,
  ) {
    final byId = <String, MessageModel>{};
    for (final message in [...secondary, ...primary]) {
      final existing = byId[message.id];
      byId[message.id] = existing == null
          ? message
          : _preferRicherMessage(existing, message);
    }
    return byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  MessageModel _preferRicherMessage(MessageModel a, MessageModel b) =>
      _messageCompletenessScore(b) >= _messageCompletenessScore(a) ? b : a;

  int _messageCompletenessScore(MessageModel message) {
    var score = 0;
    if (message.text.isNotEmpty) {
      score++;
    }
    if (message.modelUrl != null && message.modelUrl!.isNotEmpty) {
      score += 3;
    }
    if (message.workflowId != null && message.workflowId!.isNotEmpty) {
      score += 3;
    }
    if (message.operation != null && message.operation!.isNotEmpty) {
      score += 2;
    }
    if (message.messageType != null && message.messageType!.isNotEmpty) {
      score += 2;
    }
    if (message.sourceModelUrl != null && message.sourceModelUrl!.isNotEmpty) {
      score++;
    }
    if (message.modelArtifact != null) {
      score += 2;
    }
    if (message.codeArtifact != null) {
      score += 2;
    }
    if (message.jointsArtifact != null) {
      score += 2;
    }
    score += message.joints.length;
    return score;
  }
}
