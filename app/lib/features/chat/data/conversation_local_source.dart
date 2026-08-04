import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLegacyConversationsKey = 'local_conversations';
const _kConversationsPrefix = 'local_conversations_';
const _kMessagesPrefix = 'local_messages_';
const _kMaxCachedConversations = 500;
const _kMaxConversationCacheChars = 2 * 1024 * 1024;
const _kStorageTimeout = Duration(seconds: 1);

class ConversationLocalSource {
  String _conversationsKey(String userId) =>
      '$_kConversationsPrefix${Uri.encodeComponent(userId)}';

  Future<List<ConversationModel>> loadConversations(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _kStorageTimeout,
      );
      // The pre-user-scoping cache cannot be safely attributed on a shared
      // browser. Drop it once instead of briefly showing it to the next user.
      unawaited(_removeLegacyCache(prefs));
      final raw = prefs.getString(_conversationsKey(userId));
      if (raw == null) return [];
      // JSON decoding is synchronous on web. Reject an unexpectedly large or
      // corrupted cache before parsing so local storage can never pin startup.
      if (raw.length > _kMaxConversationCacheChars) {
        debugPrint(
          '[ConversationLocalSource] ignored oversized cache '
          '(${raw.length} chars)',
        );
        return [];
      }
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .take(_kMaxCachedConversations)
          .map(ConversationModel.fromJson)
          .toList();
    } catch (e, st) {
      debugPrint('[ConversationLocalSource] load failed: $e\n$st');
      // The backend is authoritative. A slow, unavailable, or corrupt local
      // cache must behave exactly like a cache miss and never gate the sidebar.
      return [];
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
  Future<void> save(String userId, List<ConversationModel> convs) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _kStorageTimeout,
      );
      final encoded = json.encode(
        convs.take(_kMaxCachedConversations).map(_toCacheEntry).toList(),
      );
      if (encoded.length > _kMaxConversationCacheChars) return;
      await prefs
          .setString(_conversationsKey(userId), encoded)
          .timeout(_kStorageTimeout);
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

  Future<void> _removeLegacyCache(SharedPreferences prefs) async {
    try {
      await prefs.remove(_kLegacyConversationsKey).timeout(_kStorageTimeout);
    } catch (_) {
      // Best-effort migration cleanup; the user-scoped key is still safe.
    }
  }

  // Non-fatal cleanup — orphaned message data in storage is acceptable.
  Future<void> deleteMessages(String convId) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _kStorageTimeout,
      );
      await prefs.remove('$_kMessagesPrefix$convId').timeout(_kStorageTimeout);
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
      final prefs = await SharedPreferences.getInstance().timeout(
        _kStorageTimeout,
      );
      final toRemove = prefs
          .getKeys()
          .where(
            (k) =>
                k == _kLegacyConversationsKey ||
                k.startsWith(_kConversationsPrefix) ||
                k.startsWith(_kMessagesPrefix),
          )
          .toList();
      await Future.wait(toRemove.map(prefs.remove)).timeout(_kStorageTimeout);
    } catch (e, st) {
      debugPrint('[ConversationLocalSource] clearAll failed: $e\n$st');
    }
  }
}
