import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/features/chat/data/chat_snapshot_codec.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kMessagesPrefix = 'local_messages_';
const _kMaxCachedMessages = 1000;
const _kMaxMessageCacheChars = 8 * 1024 * 1024;
const _kStorageTimeout = Duration(seconds: 1);

class MessageLocalSource {
  Future<List<MessageModel>> loadMessages(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _kStorageTimeout,
      );
      final raw = prefs.getString('$_kMessagesPrefix$conversationId');
      if (raw == null) return [];
      // Message caches can contain image data. Bound the synchronous web JSON
      // parse so a stale oversized value cannot freeze conversation startup.
      if (raw.length > _kMaxMessageCacheChars) {
        debugPrint(
          '[MessageLocalSource] ignored oversized cache for $conversationId '
          '(${raw.length} chars)',
        );
        return [];
      }
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .take(_kMaxCachedMessages)
          .map(MessageModel.fromLocalJson)
          .toList();
    } catch (e, st) {
      debugPrint('[MessageLocalSource] load($conversationId) failed: $e\n$st');
      // Remote messages/snapshots are authoritative. Treat local failures as a
      // cache miss so opening a conversation always remains responsive.
      return [];
    }
  }

  /// Persists a conversation's messages as a best-effort local cache. The
  /// backend remains the source of truth, so a write failure (e.g. a storage
  /// quota error) is logged and swallowed rather than propagated — this runs
  /// fire-and-forget, so throwing here would surface as an uncaught async error.
  Future<void> save(String conversationId, List<MessageModel> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _kStorageTimeout,
      );
      final encoded = json.encode(
        messages
            .take(_kMaxCachedMessages)
            .map((message) => message.toLocalJson())
            .toList(),
      );
      if (encoded.length > _kMaxMessageCacheChars) return;
      await prefs
          .setString('$_kMessagesPrefix$conversationId', encoded)
          .timeout(_kStorageTimeout);
    } catch (e, st) {
      debugPrint(
        '[MessageLocalSource] save($conversationId) failed (ignored): $e\n$st',
      );
    }
  }

  /// Seeds message storage from snapshot data already embedded in the given
  /// conversations. Only writes for conversations with no existing local entry
  /// so that richer local state (e.g. an in-progress generation) is preserved.
  Future<void> seedFromSnapshots(List<ConversationModel> conversations) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _kStorageTimeout,
      );
      for (final conv in conversations) {
        final key = '$_kMessagesPrefix${conv.id}';
        if (prefs.containsKey(key)) continue;
        final messages = parseChatSnapshotMessages(
          conv.metadata,
        ).take(_kMaxCachedMessages).toList();
        if (messages.isEmpty) continue;
        final encoded = json.encode(
          messages.map((message) => message.toLocalJson()).toList(),
        );
        if (encoded.length > _kMaxMessageCacheChars) continue;
        await prefs.setString(key, encoded).timeout(_kStorageTimeout);
      }
    } catch (e, st) {
      debugPrint('[MessageLocalSource] seedFromSnapshots failed: $e\n$st');
    }
  }
}
