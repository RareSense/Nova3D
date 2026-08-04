import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/features/chat/data/chat_service.dart';
import 'package:nova3d_frontend/features/chat/data/chat_snapshot_codec.dart';
import 'package:nova3d_frontend/features/chat/data/conversation_local_source.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

class ConversationRepository {
  ConversationRepository(this._local, this._remote, {required String? userId})
    : _userId = userId;

  final ConversationLocalSource _local;
  final ChatService _remote;
  final String? _userId;
  final Map<String, Timer> _snapshotDebounce = {};
  final Set<String> _messagePersistKeys = {};
  bool _disposed = false;

  Future<List<ConversationModel>> load() => _loadLocal();

  Future<List<ConversationModel>> _loadLocal() {
    final userId = _userId;
    return userId == null
        ? Future.value(<ConversationModel>[])
        : _local.loadConversations(userId);
  }

  Future<void> _saveLocal(List<ConversationModel> conversations) {
    final userId = _userId;
    if (userId == null || _disposed) return Future<void>.value();
    return _local.save(userId, conversations);
  }

  /// Syncs the conversation list from the backend.
  ///
  /// The backend returns each conversation's full metadata snapshot inline, so
  /// the list is fetched in small pages rather than one request. This bounds
  /// the size of any single response the browser must download and parse,
  /// keeping history loadable even while older conversations still carry heavy
  /// (pre-trim) snapshots. [maxConversations] caps the walk so a growing list
  /// can never loop unbounded. The first page is fetched alone and published
  /// immediately; later pages are fetched in small concurrent batches so deep
  /// histories do not require one network round-trip per page.
  Future<List<ConversationModel>> syncLatest({
    int pageSize = 50,
    int maxConversations = 500,
    int maxConcurrentPages = 3,
    Duration syncTimeout = const Duration(seconds: 30),
    void Function(List<ConversationModel> conversations)? onPage,
  }) async {
    if (_userId == null || _disposed) return <ConversationModel>[];
    final effectivePageSize = pageSize.clamp(1, 50).toInt();
    final effectiveMaxConversations = maxConversations.clamp(1, 500).toInt();
    final effectiveConcurrency = maxConcurrentPages.clamp(1, 3).toInt();
    final deadline = DateTime.now().add(syncTimeout);

    Duration remainingTime() {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'Conversation history sync exceeded ${syncTimeout.inSeconds}s.',
        );
      }
      return remaining;
    }

    final local = await _loadLocal().timeout(
      remainingTime(),
      onTimeout: () => <ConversationModel>[],
    );
    if (_disposed) return local.take(effectiveMaxConversations).toList();
    final remote = <ConversationModel>[];
    var merged = _mergeConversations(
      local,
      remote,
    ).take(effectiveMaxConversations).toList();

    Future<_ConversationPageResult> fetchPage(int offset) async {
      try {
        final page = await _remote
            .getConversations(limit: effectivePageSize, offset: offset)
            .timeout(remainingTime());
        if (_disposed) {
          return _ConversationPageResult(offset: offset, page: const []);
        }

        final remainingSlots = effectiveMaxConversations - remote.length;
        if (remainingSlots > 0) {
          remote.addAll(page.take(remainingSlots));
          merged = _mergeConversations(
            local,
            remote,
          ).take(effectiveMaxConversations).toList();
          onPage?.call(merged);
        }
        return _ConversationPageResult(offset: offset, page: page);
      } catch (error, stackTrace) {
        return _ConversationPageResult(
          offset: offset,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    try {
      // Fetch page zero by itself so useful history is visible after one
      // request, regardless of how deep the account's history is.
      final first = await fetchPage(0);
      if (first.error != null) {
        Error.throwWithStackTrace(first.error!, first.stackTrace!);
      }
      if (_disposed) return local.take(effectiveMaxConversations).toList();
      unawaited(_saveLocal(merged));

      var nextOffset = effectivePageSize;
      var reachedEnd = first.page.length < effectivePageSize;

      while (!reachedEnd &&
          remote.length < effectiveMaxConversations &&
          nextOffset < effectiveMaxConversations) {
        remainingTime();
        final offsets = <int>[];
        while (offsets.length < effectiveConcurrency &&
            nextOffset < effectiveMaxConversations) {
          offsets.add(nextOffset);
          nextOffset += effectivePageSize;
        }

        // Every future converts failures into a result, so the whole bounded
        // batch settles before we decide whether to stop. No late page can
        // mutate state after this method reports a failure.
        final results = await Future.wait(offsets.map(fetchPage));
        results.sort((a, b) => a.offset.compareTo(b.offset));

        Object? firstError;
        StackTrace? firstStackTrace;
        for (final result in results) {
          if (result.error != null && firstError == null) {
            firstError = result.error;
            firstStackTrace = result.stackTrace;
          }
          if (result.page.length < effectivePageSize) reachedEnd = true;
        }
        if (firstError != null) {
          Error.throwWithStackTrace(firstError, firstStackTrace!);
        }
      }
    } catch (_) {
      // Keep every successfully fetched page available on the next launch,
      // while still rethrowing so callers can record/report the partial sync.
      unawaited(_saveLocal(merged));
      rethrow;
    }
    unawaited(_saveLocal(merged));
    return merged;
  }

  Future<ConversationModel> create(String title) async {
    final conv = await _remote.createConversation(title);
    final current = await _loadLocal();
    await _saveLocal(_mergeConversations([conv, ...current], const []));
    return conv;
  }

  Future<void> persist(List<ConversationModel> convs) => _saveLocal(convs);

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
        if (_disposed) return;
        final current = await _loadLocal();
        await _saveLocal(_mergeConversations(current, [updated]));
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
    _disposed = true;
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
      // On equal timestamps the later-iterated source wins. Callers pass the
      // more authoritative list second (remote after the local summary cache,
      // or the updated conversation after the current set), so its richer
      // fields — e.g. the metadata snapshot the local cache omits — are kept.
      if (existing == null || !conv.updatedAt.isBefore(existing.updatedAt)) {
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

class _ConversationPageResult {
  const _ConversationPageResult({
    required this.offset,
    this.page = const <ConversationModel>[],
    this.error,
    this.stackTrace,
  });

  final int offset;
  final List<ConversationModel> page;
  final Object? error;
  final StackTrace? stackTrace;
}
