import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/core/errors.dart';
import 'package:nova3d_frontend/features/chat/data/chat_snapshot_codec.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kMessagesPrefix = 'local_messages_';

class MessageLocalSource {
  Future<List<MessageModel>> loadMessages(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_kMessagesPrefix$conversationId');
      if (raw == null) return [];
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MessageModel.fromLocalJson)
          .toList();
    } catch (e, st) {
      debugPrint('[MessageLocalSource] load($conversationId) failed: $e\n$st');
      throw AppError(
        'Failed to load messages from storage.',
        kind: AppErrorKind.persistence,
        cause: e,
      );
    }
  }

  Future<void> save(String conversationId, List<MessageModel> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_kMessagesPrefix$conversationId',
        json.encode(messages.map((m) => m.toLocalJson()).toList()),
      );
    } catch (e, st) {
      debugPrint('[MessageLocalSource] save($conversationId) failed: $e\n$st');
      throw AppError(
        'Failed to persist messages.',
        kind: AppErrorKind.persistence,
        cause: e,
      );
    }
  }

  /// Seeds message storage from snapshot data already embedded in the given
  /// conversations. Only writes for conversations with no existing local entry
  /// so that richer local state (e.g. an in-progress generation) is preserved.
  Future<void> seedFromSnapshots(List<ConversationModel> conversations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final conv in conversations) {
        final key = '$_kMessagesPrefix${conv.id}';
        if (prefs.containsKey(key)) continue;
        final messages = parseChatSnapshotMessages(conv.metadata);
        if (messages.isEmpty) continue;
        await prefs.setString(
          key,
          json.encode(messages.map((m) => m.toLocalJson()).toList()),
        );
      }
    } catch (e, st) {
      debugPrint('[MessageLocalSource] seedFromSnapshots failed: $e\n$st');
    }
  }
}
