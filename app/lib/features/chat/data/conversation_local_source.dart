import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/core/errors.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kConversationsKey = 'local_conversations';
const _kMessagesPrefix = 'local_messages_';

class ConversationLocalSource {
  Future<List<ConversationModel>> loadConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kConversationsKey);
      if (raw == null) return [];
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ConversationModel.fromJson)
          .toList();
    } catch (e, st) {
      debugPrint('[ConversationLocalSource] load failed: $e\n$st');
      throw AppError(
        'Failed to load conversations from storage.',
        kind: AppErrorKind.persistence,
        cause: e,
      );
    }
  }

  /// Persists the conversation list as a best-effort local summary cache.
  ///
  /// Only lightweight summary fields are stored: the heavy
  /// [ConversationModel.metadata] snapshot (which can embed base64 reference
  /// images and reach several MB per conversation) is intentionally dropped so
  /// the cache stays well within the browser's localStorage quota. Message
  /// content is re-fetched from the backend when a conversation is opened.
  ///
  /// The backend is the source of truth, so a write failure (e.g. a quota or
  /// private-mode error) is logged and swallowed — persisting the cache must
  /// never discard conversation data the caller already fetched.
  Future<void> save(List<ConversationModel> convs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kConversationsKey,
        json.encode(convs.map(_toCacheEntry).toList()),
      );
    } catch (e, st) {
      debugPrint('[ConversationLocalSource] save failed (ignored): $e\n$st');
    }
  }

  /// Serializes a conversation for the local summary cache, omitting the heavy
  /// metadata snapshot. See [save] for why metadata is not cached.
  static Map<String, dynamic> _toCacheEntry(ConversationModel conv) {
    final entry = conv.toJson();
    entry.remove('conversation_metadata');
    return entry;
  }

  // Non-fatal cleanup — orphaned message data in storage is acceptable.
  Future<void> deleteMessages(String convId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kMessagesPrefix$convId');
    } catch (e, st) {
      debugPrint(
        '[ConversationLocalSource] deleteMessages($convId) failed: $e\n$st',
      );
    }
  }

  /// Removes all conversation and message data for any user from local storage.
  /// Called on logout to prevent data leaking into the next user's session.
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toRemove = prefs
          .getKeys()
          .where(
            (k) => k == _kConversationsKey || k.startsWith(_kMessagesPrefix),
          )
          .toList();
      for (final key in toRemove) {
        await prefs.remove(key);
      }
    } catch (e, st) {
      debugPrint('[ConversationLocalSource] clearAll failed: $e\n$st');
    }
  }
}
