import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/analytics/analytics.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/data/generation_analytics.dart';
import 'package:nova3d_frontend/features/cad/models/asset_version.dart';
import 'package:nova3d_frontend/features/cad/models/cad_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';
import 'package:nova3d_frontend/features/cad/models/texture_draft.dart';
import 'package:nova3d_frontend/features/cad/models/texture_request.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/features/chat/data/chat_service.dart';
import 'package:nova3d_frontend/features/chat/data/conversation_local_source.dart';
import 'package:nova3d_frontend/features/chat/data/conversation_repository.dart';
import 'package:nova3d_frontend/features/chat/data/message_local_source.dart';
import 'package:nova3d_frontend/features/chat/data/message_repository.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/models/user_model.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';
import 'package:nova3d_frontend/features/subscription/state/billing_provider.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref.watch(authServiceProvider));
});

final conversationLocalSourceProvider = Provider<ConversationLocalSource>(
  (_) => ConversationLocalSource(),
);

final messageLocalSourceProvider = Provider<MessageLocalSource>(
  (_) => MessageLocalSource(),
);

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final userId = ref.watch(authProvider.select((auth) => auth.valueOrNull?.id));
  final repo = ConversationRepository(
    ref.watch(conversationLocalSourceProvider),
    ref.watch(chatServiceProvider),
    userId: userId,
  );
  ref.onDispose(repo.cancelPendingTimers);
  return repo;
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(ref.watch(messageLocalSourceProvider));
});

// ── Conversations ─────────────────────────────────────────────────────────────

class ConversationsNotifier extends AsyncNotifier<List<ConversationModel>> {
  @override
  Future<List<ConversationModel>> build() async {
    // Clear persisted user data on explicit logout (authenticated → null
    // transition only; ignores the initial loading → null startup path).
    ref.listen<AsyncValue<UserModel?>>(authProvider, (previous, next) {
      final wasLoggedIn = previous?.valueOrNull != null;
      final isNowLoggedOut = next is AsyncData && next.value == null;
      if (wasLoggedIn && isNowLoggedOut) {
        ref.read(conversationRepositoryProvider).cancelPendingTimers();
        unawaited(ref.read(conversationLocalSourceProvider).clearAll());
      }
    });

    // Rebuild automatically whenever the authenticated user changes so that
    // a newly logged-in user never sees another user's in-memory conversations.
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return [];

    final cacheTimer = Stopwatch()..start();
    final local = await ref.read(conversationRepositoryProvider).load();
    analytics.capture(Ev.conversationHistoryCacheLoaded, <String, Object?>{
      Pr.durationMs: cacheTimer.elapsedMilliseconds,
      Pr.conversationCount: local.length,
    });
    Future.microtask(_syncLatest);
    return local;
  }

  Future<ConversationModel> create(String title) async {
    final conv = await ref.read(conversationRepositoryProvider).create(title);
    await prepend(conv);
    return conv;
  }

  Future<void> _syncLatest() async {
    final userId = ref.read(authProvider).valueOrNull?.id;
    if (userId == null) return;
    final timer = Stopwatch()..start();
    final cachedCount = state.valueOrNull?.length ?? 0;
    var pageCount = 0;
    analytics.capture(Ev.conversationHistorySyncStarted, <String, Object?>{
      Pr.cachedCount: cachedCount,
    });
    try {
      final synced = await ref
          .read(conversationRepositoryProvider)
          .syncLatest(
            onPage: (page) {
              // A logout/login can complete while an old user's request is in
              // flight. Never publish that stale response into the new session.
              if (ref.read(authProvider).valueOrNull?.id != userId) return;
              pageCount++;
              state = AsyncValue.data(page);
              if (pageCount == 1) {
                analytics.capture(
                  Ev.conversationHistoryFirstPageLoaded,
                  <String, Object?>{
                    Pr.durationMs: timer.elapsedMilliseconds,
                    Pr.conversationCount: page.length,
                    Pr.cachedCount: cachedCount,
                  },
                );
              }
            },
          );
      if (ref.read(authProvider).valueOrNull?.id != userId) return;
      state = AsyncValue.data(synced);
      analytics.capture(Ev.conversationHistorySyncSucceeded, <String, Object?>{
        Pr.durationMs: timer.elapsedMilliseconds,
        Pr.pageCount: pageCount,
        Pr.conversationCount: synced.length,
        Pr.cachedCount: cachedCount,
      });
    } catch (error) {
      analytics.capture(Ev.conversationHistorySyncFailed, <String, Object?>{
        Pr.durationMs: timer.elapsedMilliseconds,
        Pr.pageCount: pageCount,
        Pr.conversationCount: state.valueOrNull?.length ?? cachedCount,
        Pr.cachedCount: cachedCount,
        Pr.errorMessage: error.toString(),
      });
      // The local cache (plus any pages already published by onPage) remains
      // authoritative when the rest of remote history is unavailable.
    }
  }

  Future<void> prepend(ConversationModel conv) async {
    final updated = <ConversationModel>[
      conv,
      ...(state.valueOrNull ?? <ConversationModel>[]).where(
        (item) => item.id != conv.id,
      ),
    ];
    state = AsyncValue.data(updated);
    await ref.read(conversationRepositoryProvider).persist(updated);
  }

  Future<void> remove(String id) async {
    final updated = (state.valueOrNull ?? <ConversationModel>[])
        .where((c) => c.id != id)
        .toList();
    state = AsyncValue.data(updated);
    await ref.read(conversationRepositoryProvider).persist(updated);
    await ref.read(conversationRepositoryProvider).delete(id);
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<ConversationModel>>(
      ConversationsNotifier.new,
    );

// ── Generation draft ──────────────────────────────────────────────────────────

class GenerationDraftsNotifier
    extends Notifier<Map<String, GenerationRequest>> {
  @override
  Map<String, GenerationRequest> build() {
    // Reset drafts whenever the authenticated user changes (login/logout).
    ref.watch(authProvider);
    return {};
  }

  void put(String conversationId, GenerationRequest request) =>
      state = {...state, conversationId: request};

  GenerationRequest? take(String conversationId) {
    final req = state[conversationId];
    if (req == null) return null;
    state = Map.from(state)..remove(conversationId);
    return req;
  }

  GenerationRequest? peek(String conversationId) => state[conversationId];
}

final generationDraftsProvider =
    NotifierProvider<GenerationDraftsNotifier, Map<String, GenerationRequest>>(
      GenerationDraftsNotifier.new,
    );

// ── Texture draft ───────────────────────────────────────────────────────────
// Hands a showcase-originated texture run off to the chat page, exactly like
// [GenerationDraftsNotifier] does for generations: the launcher stashes a draft
// keyed by the new conversation id, then [ChatPage] takes it once on mount and
// starts the run. Keyed by conversation id because each texture run gets its own
// fresh conversation, so there is never more than one draft per key.

class TextureDraftsNotifier extends Notifier<Map<String, TextureDraft>> {
  @override
  Map<String, TextureDraft> build() {
    // Reset drafts whenever the authenticated user changes (login/logout).
    ref.watch(authProvider);
    return {};
  }

  void put(String conversationId, TextureDraft draft) =>
      state = {...state, conversationId: draft};

  TextureDraft? take(String conversationId) {
    final draft = state[conversationId];
    if (draft == null) return null;
    state = Map.from(state)..remove(conversationId);
    return draft;
  }
}

final textureDraftsProvider =
    NotifierProvider<TextureDraftsNotifier, Map<String, TextureDraft>>(
      TextureDraftsNotifier.new,
    );

// ── Messages ──────────────────────────────────────────────────────────────────

class ChatMessagesState {
  const ChatMessagesState({required this.messages, this.loaded = false});

  final List<MessageModel> messages;
  final bool loaded;

  ChatMessagesState copyWith({List<MessageModel>? messages, bool? loaded}) =>
      ChatMessagesState(
        messages: messages ?? this.messages,
        loaded: loaded ?? this.loaded,
      );
}

class MessagesNotifier
    extends AutoDisposeFamilyAsyncNotifier<ChatMessagesState, String> {
  bool _busy = false;

  // Workflow ids this notifier instance is already polling (via an active send
  // or a resume). A workflow is polled at most once per instance, so a
  // remote-snapshot-triggered resume can never start a duplicate poller.
  final Set<String> _pollingWorkflowIds = {};

  // Source generation message ids with an in-flight texture run, so a double
  // click / re-entrancy cannot launch two texture workflows for one model.
  final Set<String> _texturingSources = {};

  // A run cannot exceed the workflow runtime cap (7200s). A message still
  // "in progress" older than this on load is from a dead run and is settled
  // immediately rather than resumed.
  static const Duration _maxWorkflowLifetime = Duration(hours: 2, minutes: 30);

  // Stores a seeded state if seed() is called before build() completes.
  // build() checks this after the async load and returns it instead of [].
  ChatMessagesState? _pendingSeed;

  @override
  Future<ChatMessagesState> build(String conversationId) async {
    final msgs = await ref.read(messageRepositoryProvider).load(conversationId);

    // If sendGeneration already ran while we were awaiting the IO (race:
    // addPostFrameCallback fired before build() completed), its state is
    // already correct. Returning _pendingSeed here would override it and
    // create a second orphaned assistant message. Preserve the live state.
    final live = state;
    if (live is AsyncData<ChatMessagesState> &&
        live.value.messages.isNotEmpty) {
      _pendingSeed = null;
      return live.value;
    }

    // seed() may have run while we were loading (home_page calls it before
    // navigating). Return the seeded state so the optimistic UI is preserved.
    if (_pendingSeed != null) {
      final seeded = _pendingSeed!;
      _pendingSeed = null;
      _save(seeded.messages);
      return seeded;
    }

    final initial = ChatMessagesState(messages: msgs, loaded: true);
    Future.microtask(_syncRemoteSnapshot);
    Future.microtask(_resumeActiveGenerations);
    return initial;
  }

  // ── Persistence helpers ────────────────────────────────────────────────────

  List<MessageModel> get _messages => state.valueOrNull?.messages ?? [];

  ConversationModel? get _conversation {
    final convs = ref.read(conversationsProvider).valueOrNull;
    if (convs == null) return null;
    for (final conv in convs) {
      if (conv.id == arg) return conv;
    }
    return null;
  }

  void _save(List<MessageModel> msgs, {bool immediateRemote = false}) {
    // Fire-and-forget — errors are logged by MessageLocalSource.
    unawaited(ref.read(messageRepositoryProvider).persist(arg, msgs));
    final conv = _conversation;
    if (conv != null) {
      unawaited(
        ref
            .read(conversationRepositoryProvider)
            .persistMessagesSnapshot(
              conversation: conv,
              messages: msgs,
              immediate: immediateRemote,
            ),
      );
    }
  }

  Future<void> _syncRemoteSnapshot() async {
    try {
      final remoteMessages = await ref
          .read(conversationRepositoryProvider)
          .loadRemoteMessages(arg, cachedMetadata: _conversation?.metadata);
      if (remoteMessages.isEmpty) return;
      final merged = _mergeRemoteMessages(_messages, remoteMessages);
      if (_sameMessageIds(_messages, merged)) return;
      state = AsyncValue.data(
        ChatMessagesState(messages: merged, loaded: true),
      );
      unawaited(ref.read(messageRepositoryProvider).persist(arg, merged));
      _resumeActiveGenerations();
    } catch (_) {
      // The local empty state is still valid for unsynced or deleted chats.
    }
  }

  List<MessageModel> _mergeRemoteMessages(
    List<MessageModel> local,
    List<MessageModel> remote,
  ) {
    final byId = <String, MessageModel>{};
    for (final message in local) {
      byId[message.id] = message;
    }
    for (final message in remote) {
      final existing = byId[message.id];
      if (existing == null || !existing.isStreaming) {
        // Deletion is monotonic and may not have reached the remote snapshot
        // yet (the snapshot push is debounced) — a stale remote copy must
        // never resurrect a message the user already deleted.
        byId[message.id] =
            (existing != null && existing.isDeleted && !message.isDeleted)
            ? message.copyWith(deletedAt: existing.deletedAt)
            : message;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  bool _sameMessageIds(List<MessageModel> a, List<MessageModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].modelUrl != b[i].modelUrl ||
          a[i].workflowId != b[i].workflowId ||
          a[i].operation != b[i].operation ||
          a[i].messageType != b[i].messageType ||
          a[i].sourceModelUrl != b[i].sourceModelUrl ||
          a[i].deletedAt != b[i].deletedAt) {
        return false;
      }
    }
    return true;
  }

  void _resumeActiveGenerations() {
    final active = _messages
        .where(
          (m) =>
              m.role == MessageRole.assistant &&
              !m.isDeleted &&
              m.workflowId != null &&
              m.workflowId!.isNotEmpty &&
              m.modelUrl == null,
        )
        .toList();
    bool isTexture(MessageModel m) =>
        m.messageType == 'texture' || m.operation == 'texture_3d';

    for (final msg in active) {
      final workflowId = msg.workflowId!;
      // Idempotency: never start a second poller for a workflow already being
      // polled by this instance (a live send, or an earlier resume pass).
      if (!_pollingWorkflowIds.add(workflowId)) continue;

      // A run cannot outlive the workflow runtime cap. A message still marked
      // "in progress" older than that is a leftover from a dead run (e.g. the
      // tab was closed mid-run) — settle it as failed on load instead of
      // resuming a poll, so it never lingers as an endlessly-spinning card.
      if (DateTime.now().difference(msg.createdAt) > _maxWorkflowLifetime) {
        _upsert(
          msg.copyWith(
            text: isTexture(msg)
                ? 'This texturing run did not finish. Reopen ✨ Texture to try again.'
                : 'This run did not finish. Please try again.',
            isStreaming: false,
            clearRetryRequest: true,
          ),
          immediateRemote: true,
        );
        continue;
      }

      if (isTexture(msg)) {
        _upsert(
          msg.copyWith(
            text: 'Checking texturing status...',
            isStreaming: true,
            clearRetryRequest: true,
          ),
        );
        _resumeTexturing(msg);
        continue;
      }

      _upsert(
        msg.copyWith(
          text: 'Checking generation status...',
          isStreaming: true,
          clearRetryRequest: true,
        ),
      );
      analytics.capture(Ev.generationResumed, <String, Object?>{
        Pr.workflowId: workflowId,
        Pr.modelOptionId: msg.modelOptionId,
        Pr.surface: Surface.chat,
      });
      _busy = true;
      _pollExistingGeneration(
        workflowId: workflowId,
        assistantId: msg.id,
        assistantCreatedAt: msg.createdAt,
        modelOptionId: msg.modelOptionId,
        modelLabel: msg.modelLabel,
      );
    }
  }

  // ── Optimistic seed ────────────────────────────────────────────────────────

  void seed(GenerationRequest request) {
    if (_busy) return;
    final current = state.valueOrNull;
    if (current != null && current.messages.isNotEmpty) return;

    final now = DateTime.now();
    final seeded = ChatMessagesState(
      messages: [
        MessageModel(
          id: 'user-${now.millisecondsSinceEpoch}',
          role: MessageRole.user,
          text: request.prompt,
          createdAt: now,
          imageDataUrls: request.imageDataUrls,
        ),
        MessageModel(
          id: 'cad-${now.millisecondsSinceEpoch}',
          role: MessageRole.assistant,
          text: 'Starting generation…',
          createdAt: now,
          isStreaming: true,
        ),
      ],
      loaded: true,
    );

    if (state.isLoading) {
      // build() is still running — store for it to return and persist now.
      _pendingSeed = seeded;
      _save(seeded.messages);
    } else {
      state = AsyncValue.data(seeded);
      _save(seeded.messages);
    }
  }

  // ── Generation ─────────────────────────────────────────────────────────────

  Future<void> sendGeneration(GenerationRequest request) async {
    if (_busy) return;
    if (!request.hasText && !request.hasImage) return;
    _busy = true;

    final now = DateTime.now();
    final workflowId = CadService.createWorkflowId();

    String userId;
    String assistantId;
    DateTime assistantCreatedAt;

    if (_messages.isNotEmpty && _messages.any((m) => m.isStreaming)) {
      final seededUser = _messages.firstWhere(
        (m) => m.role == MessageRole.user,
      );
      final seededAsst = _messages.firstWhere(
        (m) => m.role == MessageRole.assistant,
      );
      userId = seededUser.id;
      assistantId = seededAsst.id;
      assistantCreatedAt = seededAsst.createdAt;
      state = AsyncValue.data(
        ChatMessagesState(
          messages: [
            seededUser.copyWith(text: request.prompt),
            seededAsst.copyWith(
              text: 'Starting generation…',
              isStreaming: true,
              workflowId: workflowId,
            ),
          ],
          loaded: true,
        ),
      );
    } else {
      userId = 'user-${now.millisecondsSinceEpoch}';
      assistantId = 'cad-${now.millisecondsSinceEpoch}';
      assistantCreatedAt = now;
      final updated = [
        ..._messages,
        MessageModel(
          id: userId,
          role: MessageRole.user,
          text: request.prompt,
          createdAt: now,
          imageDataUrls: request.imageDataUrls,
        ),
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: 'Starting generation…',
          createdAt: now,
          isStreaming: true,
          workflowId: workflowId,
        ),
      ];
      state = AsyncValue.data(
        ChatMessagesState(messages: updated, loaded: true),
      );
    }
    _save(_messages);

    await _runGeneration(
      request: request,
      assistantId: assistantId,
      assistantCreatedAt: assistantCreatedAt,
      workflowId: workflowId,
    );
  }

  Future<void> _runGeneration({
    required GenerationRequest request,
    required String assistantId,
    required DateTime assistantCreatedAt,
    required String workflowId,
  }) async {
    final cad = ref.read(cadServiceProvider);
    final tracker = WorkflowRunTracker.forGeneration(request);
    final requestProps = generationRequestProperties(request);
    try {
      await _ensurePaidCreditBudget(request, cad);
      final startedWorkflowId = await cad.startGeneration(
        request,
        workflowId: workflowId,
        conversationId: arg,
      );
      tracker.start(startedWorkflowId);
      analytics.capture(Ev.generationStarted, <String, Object?>{
        ...requestProps,
        Pr.workflowId: startedWorkflowId,
      });
      // Register the live run before publishing its streaming message. This is
      // the same idempotency guard used by resumed and texture workflows, and
      // prevents a concurrent remote-snapshot sync from starting a second
      // status poller for the same GraphFlow run.
      _pollingWorkflowIds.add(startedWorkflowId);
      await _refreshWalletForPaid(request);
      _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: 'Generating your 3D model...',
          createdAt: assistantCreatedAt,
          isStreaming: true,
          workflowId: startedWorkflowId,
          modelOptionId: request.modelOption.id,
          modelLabel: request.modelOption.persistedLabel,
        ),
      );

      final result = await _runWorkflowWithProgress(
        startedWorkflowId,
        cad: cad,
        assistantId: assistantId,
        assistantCreatedAt: assistantCreatedAt,
        modelOptionId: request.modelOption.id,
        modelLabel: request.modelOption.persistedLabel,
        tracker: tracker,
      );

      final failed = result.failed || result.glbUrl == null;
      if (failed) {
        tracker.failed(
          message: result.errorMessage,
          category: result.errorCategory,
          retryable: result.retryable,
        );
      } else {
        tracker.succeeded(
          extra: <String, Object?>{Pr.jointCount: result.jointCount},
        );
      }
      _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: failed
              ? _failureText(result.errorMessage)
              : 'Your 3D model is ready.',
          createdAt: assistantCreatedAt,
          isStreaming: false,
          modelUrl: result.glbUrl,
          workflowId: startedWorkflowId,
          modelArtifact: result.modelArtifact,
          codeArtifact: result.codeArtifact,
          jointsArtifact: result.jointsArtifact,
          joints: result.joints,
          operation: 'initial_generation',
          sourceModelUrl: result.glbUrl,
          modelOptionId: request.modelOption.id,
          modelLabel: request.modelOption.persistedLabel,
          instructionPrompt: request.prompt.trim(),
          retryRequest: failed ? request : null,
        ),
        immediateRemote: true,
      );
    } on CadException catch (e) {
      tracker.failed(message: e.message, category: 'cad_exception');
      _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: _failureText(e.message),
          createdAt: assistantCreatedAt,
          isStreaming: false,
          workflowId: workflowId,
          modelOptionId: request.modelOption.id,
          modelLabel: request.modelOption.persistedLabel,
          retryRequest: request,
        ),
        immediateRemote: true,
      );
    } catch (e, st) {
      tracker.failed(message: e.toString(), category: 'unexpected');
      // Unexpected (non-CadException) failures are a bug, not a workflow
      // outcome — send them to error tracking as well as the funnel.
      analytics.captureException(e, st, context: 'generation');
      _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: 'Failed to generate model. Please try again.',
          createdAt: assistantCreatedAt,
          isStreaming: false,
          workflowId: workflowId,
          modelOptionId: request.modelOption.id,
          modelLabel: request.modelOption.persistedLabel,
          retryRequest: request,
        ),
        immediateRemote: true,
      );
    } finally {
      await _refreshWalletForPaid(request);
      _busy = false;
    }
  }

  Future<CadResult> _runWorkflowWithProgress(
    String workflowId, {
    required CadService cad,
    required String assistantId,
    required DateTime assistantCreatedAt,
    String? modelOptionId,
    String? modelLabel,
    bool isResume = false,
    WorkflowRunTracker? tracker,
  }) {
    return cad.runWorkflow(
      workflowId,
      // A resumed workflow already existed, so "not found" means it closed —
      // fail fast instead of the long fresh-start grace.
      startupGraceRetries: isResume
          ? CadService.resumeStartupGraceRetries
          : null,
      onProgress: (status) {
        // Per-node stage timing. The tracker de-duplicates polls, so this is
        // one event per real GraphFlow transition, not one per 3s poll.
        tracker?.onStatus(status);
        _publishWorkflowProgress(
          MessageModel(
            id: assistantId,
            role: MessageRole.assistant,
            text: '',
            createdAt: assistantCreatedAt,
            isStreaming: true,
            workflowId: workflowId,
            modelOptionId: modelOptionId,
            modelLabel: modelLabel,
          ),
          status,
        );
      },
    );
  }

  /// Publishes a real GraphFlow phase only when the visible state changed.
  /// Status is polled every three seconds, so de-duplicating here avoids
  /// needless widget rebuilds, local-cache writes, and remote snapshot work.
  void _publishWorkflowProgress(MessageModel base, WorkflowStatus status) {
    final progress = status.progress;
    MessageModel? current;
    for (final message in _messages) {
      if (message.id == base.id) {
        current = message;
        break;
      }
    }
    if (current != null &&
        current.isStreaming &&
        current.workflowId == base.workflowId &&
        current.text == status.progressLabel &&
        current.workflowProgressStep == progress.step &&
        current.workflowProgressTotalSteps == progress.totalSteps &&
        current.workflowStageLabel == progress.stageLabel) {
      return;
    }
    _upsert(
      base.copyWith(
        text: status.progressLabel,
        isStreaming: true,
        workflowProgress: progress.fraction,
        workflowProgressStep: progress.step,
        workflowProgressTotalSteps: progress.totalSteps,
        workflowStageLabel: progress.stageLabel,
      ),
    );
  }

  Future<void> _pollExistingGeneration({
    required String workflowId,
    required String assistantId,
    required DateTime assistantCreatedAt,
    String? modelOptionId,
    String? modelLabel,
  }) async {
    final cad = ref.read(cadServiceProvider);
    try {
      final result = await _runWorkflowWithProgress(
        workflowId,
        cad: cad,
        assistantId: assistantId,
        assistantCreatedAt: assistantCreatedAt,
        modelOptionId: modelOptionId,
        modelLabel: modelLabel,
        isResume: true,
      );
      final failed = result.failed || result.glbUrl == null;
      _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: failed
              ? _failureText(result.errorMessage)
              : 'Your 3D model is ready.',
          createdAt: assistantCreatedAt,
          isStreaming: false,
          modelUrl: result.glbUrl,
          workflowId: workflowId,
          modelArtifact: result.modelArtifact,
          codeArtifact: result.codeArtifact,
          jointsArtifact: result.jointsArtifact,
          joints: result.joints,
          operation: 'initial_generation',
          sourceModelUrl: result.glbUrl,
          modelOptionId: modelOptionId,
          modelLabel: modelLabel,
        ),
        immediateRemote: true,
      );
    } on CadException catch (e) {
      _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: _failureText(e.message),
          createdAt: assistantCreatedAt,
          isStreaming: false,
          workflowId: workflowId,
          modelOptionId: modelOptionId,
          modelLabel: modelLabel,
        ),
        immediateRemote: true,
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _ensurePaidCreditBudget(
    GenerationRequest request,
    CadService cad,
  ) async {
    final option = request.modelOption;
    if (!option.isPaidCredit) return;

    final estimate = await cad.estimateGenerationCredits(option);
    final required = estimate.authorizedBudget;
    analytics.capture(Ev.creditsEstimated, <String, Object?>{
      ...modelOptionProperties(option),
      Pr.projectedMaxHold: estimate.projectedMaxHold,
      Pr.authorizedBudget: estimate.authorizedBudget,
    });
    final wallet = await ref.read(billingProvider.notifier).refreshWallet();
    final available =
        wallet?.available ?? ref.read(billingProvider).wallet?.available;
    if (available == null) {
      analytics.capture(Ev.generationBlocked, <String, Object?>{
        ...modelOptionProperties(option),
        Pr.reason: 'wallet_unavailable',
        Pr.creditsRequired: required,
      });
      throw CadException(
        'Nova3D could not confirm your credit balance. Refresh credits or open /subscription, then try again.',
      );
    }
    if (available < required) {
      // The single most actionable drop-off in the funnel: the user wanted to
      // generate and could not afford it. Carries the exact shortfall.
      analytics.capture(Ev.generationBlocked, <String, Object?>{
        ...modelOptionProperties(option),
        Pr.reason: 'insufficient_credits',
        Pr.creditsRequired: required,
        Pr.creditsAvailable: available,
      });
      analytics.capture(Ev.creditsInsufficient, <String, Object?>{
        Pr.creditsRequired: required,
        Pr.creditsAvailable: available,
        Pr.surface: Surface.chat,
      });
      throw CadException(_insufficientCreditsText(required, available));
    }
  }

  Future<void> _refreshWalletForPaid(GenerationRequest request) async {
    if (!request.modelOption.isPaidCredit) return;
    await ref.read(billingProvider.notifier).refreshWallet();
  }

  /// Texture twin of [_ensurePaidCreditBudget]: hosted (keyless) texture runs
  /// are charged a workflow-level credit price, so they must clear the same
  /// balance gate before launch. BYOK runs (caller key present) cost 0 credits
  /// and skip the check entirely, like BYOK generations do.
  Future<void> _ensureTextureCreditBudget(
    TextureRequest request,
    CadService cad,
  ) async {
    if (request.hasGeminiApiKey) return;

    final estimate = await cad.estimateTextureCredits();
    final required = estimate.authorizedBudget;
    final wallet = await ref.read(billingProvider.notifier).refreshWallet();
    final available =
        wallet?.available ?? ref.read(billingProvider).wallet?.available;
    if (available == null) {
      throw CadException(
        'Nova3D could not confirm your credit balance. Refresh credits or open /subscription, then try again.',
      );
    }
    if (available < required) {
      throw CadException(
        'Texturing without an API key needs $required credits, but you have '
        '$available available. Buy more credits at /subscription or add your '
        'own Gemini key, then try again.',
      );
    }
  }

  /// Texture twin of [_refreshWalletForPaid]: hosted runs hold credits at
  /// launch and settle at completion, so the wallet refreshes at both moments;
  /// BYOK runs never touch the wallet.
  Future<void> _refreshWalletForTexture(TextureRequest request) async {
    if (request.hasGeminiApiKey) return;
    await ref.read(billingProvider.notifier).refreshWallet();
  }

  String _insufficientCreditsText(int required, int available) =>
      'This model needs $required credits, but you have $available available. Buy more credits at /subscription and try again.';

  /// Soft-deletes a message: it stays in the local store and the remote DB
  /// (`deleted_at` in its content) but is never rendered again. Streaming
  /// messages cannot be deleted (the UI hides the action; this guards direct
  /// calls too) so an active poller never updates an invisible bubble.
  void deleteMessage(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final msg = _messages[idx];
    if (msg.isStreaming || msg.isDeleted) return;
    _upsert(msg.copyWith(deletedAt: DateTime.now()), immediateRemote: true);
  }

  Future<void> retry(String failedMessageId) async {
    if (_busy) return;
    final msg = _messages.firstWhere(
      (m) => m.id == failedMessageId,
      orElse: () => throw StateError('message not found'),
    );
    if (msg.retryRequest == null) return;
    analytics.capture(Ev.generationRetried, <String, Object?>{
      ...generationRequestProperties(msg.retryRequest!),
      Pr.surface: Surface.chat,
    });
    final workflowId = CadService.createWorkflowId();
    _upsert(
      msg.copyWith(
        text: 'Retrying…',
        isStreaming: true,
        workflowId: workflowId,
        clearRetryRequest: true,
      ),
    );
    _busy = true;
    await _runGeneration(
      request: msg.retryRequest!,
      assistantId: failedMessageId,
      assistantCreatedAt: msg.createdAt,
      workflowId: workflowId,
    );
  }

  String _failureText(String? detail) {
    final clean = detail?.trim();
    if (clean == null || clean.isEmpty) {
      return 'Generation failed. Try another prompt, model, or provider key.';
    }
    if (clean.toLowerCase().startsWith('generation failed')) return clean;
    return clean;
  }

  void appendAiEditResult(AiEditCompletion completion) {
    final id = 'edit-${completion.workflowId}';
    if (_messages.any((message) => message.id == id)) return;

    _upsert(
      MessageModel(
        id: id,
        role: MessageRole.assistant,
        text: _editCompletionText(completion),
        createdAt: DateTime.now(),
        isStreaming: false,
        modelUrl: completion.modelUrl,
        workflowId: completion.workflowId,
        modelArtifact: completion.modelArtifact,
        codeArtifact: completion.codeArtifact,
        jointsArtifact: completion.jointsArtifact,
        joints: completion.joints,
        messageType: 'asset_version',
        operation: completion.operation,
        sourceModelUrl: completion.sourceModelUrl ?? completion.modelUrl,
        modelOptionId: completion.modelOptionId,
        instructionPrompt: completion.instructionPrompt,
      ),
      immediateRemote: true,
    );
  }

  String _editCompletionText(AiEditCompletion completion) {
    final description = completion.description.trim();
    final suffix = description.isEmpty ? '' : ': $description';
    return switch (completion.operation) {
      'add_3d_part' => 'Added part$suffix',
      'articulate_3d_model' => 'Articulated model$suffix',
      _ => 'Regenerated selected part$suffix',
    };
  }

  void patchArticulation(
    String messageId, {
    required String modelUrl,
    required String workflowId,
    required Map<String, dynamic>? jointsArtifact,
    required List<Map<String, dynamic>> joints,
  }) {
    final current = _messages;
    final idx = current.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final updated = [...current];
    updated[idx] = current[idx].copyWith(
      modelUrl: modelUrl,
      workflowId: workflowId,
      jointsArtifact: jointsArtifact,
      joints: joints,
    );
    state = AsyncValue.data(ChatMessagesState(messages: updated, loaded: true));
    _save(updated, immediateRemote: true);
  }

  // ── Texturing ──────────────────────────────────────────────────────────────
  // Runs `texture_3d_v2` against a specific generation's ORIGINAL geometry
  // ([sourceMessage.modelArtifact] + [sourceMessage.codeArtifact]) — never an
  // AI-edited derivative. Creates its own request/result message pair, polls
  // like a generation, and renders the textured result in the same window.
  // Independent of `_busy`: it uses per-source and per-workflow guards so it can
  // coexist with generation without races, and never blocks new generations.

  Future<void> startTexturing({
    required MessageModel sourceMessage,
    required TextureRequest request,
  }) async {
    final glbArtifact = sourceMessage.modelArtifact;
    final codeArtifact = sourceMessage.codeArtifact;
    if (glbArtifact == null || codeArtifact == null) return;
    await _beginTexturing(
      request: request,
      glbArtifact: glbArtifact,
      codeArtifact: codeArtifact,
      sourceId: sourceMessage.id,
    );
  }

  // Runs `texture_3d_v2` against an EXTERNAL source model (a showcase entry)
  // supplied as artifact refs rather than a chat message. Identical pipeline to
  // [startTexturing]; the reentrancy key is the caller-supplied [sourceId]
  // (e.g. `showcase-<entryId>`). Because each showcase texture run gets its own
  // conversation — hence its own notifier instance — this never contends with
  // another run.
  Future<void> startTexturingFromArtifacts({
    required TextureRequest request,
    required Map<String, dynamic> glbArtifact,
    required Map<String, dynamic> codeArtifact,
    required String sourceId,
  }) => _beginTexturing(
    request: request,
    glbArtifact: glbArtifact,
    codeArtifact: codeArtifact,
    sourceId: sourceId,
  );

  // Shared launch core: creates the user/assistant bubble pair and starts the
  // poll. Both the chat-message ([startTexturing]) and external-model
  // ([startTexturingFromArtifacts]) entry points funnel through here so the two
  // paths stay byte-for-byte consistent.
  Future<void> _beginTexturing({
    required TextureRequest request,
    required Map<String, dynamic> glbArtifact,
    required Map<String, dynamic> codeArtifact,
    required String sourceId,
  }) async {
    // Reentrancy guard: one in-flight texture run per source model.
    if (!_texturingSources.add(sourceId)) return;

    final now = DateTime.now();
    final workflowId = CadService.createWorkflowId();
    _pollingWorkflowIds.add(workflowId);
    final assistantId = 'texture-$workflowId';
    final promptText = request.hasPrompt ? request.prompt.trim() : null;

    // Chatting-app UX: a user request bubble + an assistant progress bubble.
    // The assistant carries the source code artifact from the start so a resume
    // after reload can pass it through to the textured result (texturing emits
    // no new program of its own).
    final userMessage = MessageModel(
      id: 'texture-user-$workflowId',
      role: MessageRole.user,
      text: promptText ?? 'Add texture to this model',
      createdAt: now,
      messageType: 'texture',
      imageDataUrls: request.hasReferenceImage
          ? [request.referenceImageDataUrl!]
          : const [],
    );
    final assistantCreatedAt = now.add(const Duration(milliseconds: 1));
    final assistantMessage = MessageModel(
      id: assistantId,
      role: MessageRole.assistant,
      text: 'Starting texturing…',
      createdAt: assistantCreatedAt,
      isStreaming: true,
      workflowId: workflowId,
      codeArtifact: codeArtifact,
      operation: 'texture_3d',
      messageType: 'texture',
      instructionPrompt: promptText,
    );
    final updated = [..._messages, userMessage, assistantMessage];
    state = AsyncValue.data(ChatMessagesState(messages: updated, loaded: true));
    _save(updated);

    await _runTexturing(
      request: request,
      glbArtifact: glbArtifact,
      codeArtifact: codeArtifact,
      sourceMessageId: sourceId,
      base: assistantMessage,
      workflowId: workflowId,
    );
  }

  Future<void> _runTexturing({
    required TextureRequest request,
    required Map<String, dynamic> glbArtifact,
    required Map<String, dynamic> codeArtifact,
    required String sourceMessageId,
    required MessageModel base,
    required String workflowId,
  }) async {
    final cad = ref.read(cadServiceProvider);
    final textureProps = <String, Object?>{
      Pr.resolution: request.resolution.label,
      Pr.isByok: request.geminiApiKey.trim().isNotEmpty,
      Pr.billingMode: request.geminiApiKey.trim().isNotEmpty
          ? 'byok'
          : 'credits',
      Pr.hasReferenceImages: request.referenceImageDataUrl != null,
      if (kCaptureUserContent && request.prompt.trim().isNotEmpty)
        Pr.prompt: request.prompt.trim(),
      Pr.promptLength: request.prompt.trim().length,
    };
    final tracker = WorkflowRunTracker.forTexture(textureProps);
    analytics.capture(Ev.textureRequested, textureProps);
    try {
      // Phase 1 — start. A failure here means the workflow never launched, so
      // the failed message carries NO workflowId: resume must not poll a
      // workflow that does not exist (which would 404-loop forever).
      // Hosted (keyless) runs must clear the credit-balance gate first,
      // exactly like paid generations.
      final String startedWorkflowId;
      try {
        await _ensureTextureCreditBudget(request, cad);
        startedWorkflowId = await cad.startTexture(
          glbArtifact: glbArtifact,
          codeArtifact: codeArtifact,
          request: request,
          workflowId: workflowId,
          conversationId: arg,
        );
      } on CadException catch (e) {
        analytics.capture(Ev.textureBlocked, <String, Object?>{
          ...textureProps,
          Pr.reason: 'start_failed',
          Pr.errorMessage: e.message,
        });
        _upsert(
          _startFailureMessage(base, _failureText(e.message)),
          immediateRemote: true,
        );
        return;
      }

      // Phase 2 — poll. The workflow exists now, so the message keeps its id;
      // a poll failure is terminal (the workflow itself failed) and resume can
      // safely re-check it without looping.
      await _refreshWalletForTexture(request); // show the credit hold
      tracker.start(startedWorkflowId);
      analytics.capture(Ev.textureStarted, <String, Object?>{
        ...textureProps,
        Pr.workflowId: startedWorkflowId,
      });
      _pollingWorkflowIds.add(startedWorkflowId);
      _upsert(
        base.copyWith(
          text: 'Texturing your model…',
          isStreaming: true,
          workflowId: startedWorkflowId,
        ),
      );

      final result = await cad.runTextureWorkflow(
        startedWorkflowId,
        onProgress: (status) {
          tracker.onStatus(status);
          _publishWorkflowProgress(
            base.copyWith(isStreaming: true, workflowId: startedWorkflowId),
            status,
          );
        },
      );

      final failed = result.failed || result.glbUrl == null;
      if (failed) {
        tracker.failed(message: result.errorMessage);
      } else {
        tracker.succeeded(
          extra: <String, Object?>{Pr.assetCount: result.assets.length},
        );
      }
      _upsert(
        base.copyWith(
          text: failed
              ? _failureText(result.errorMessage)
              : 'Your textured model is ready.',
          isStreaming: false,
          workflowId: startedWorkflowId,
          modelUrl: result.glbUrl,
          modelArtifact: result.modelArtifact,
          sourceModelUrl: result.glbUrl,
          textureAssets: result.assets.map((a) => a.toJson()).toList(),
        ),
        immediateRemote: true,
      );
    } on CadException catch (e) {
      tracker.failed(message: e.message, category: 'cad_exception');
      _upsert(
        base.copyWith(text: _failureText(e.message), isStreaming: false),
        immediateRemote: true,
      );
    } catch (e, st) {
      tracker.failed(message: e.toString(), category: 'unexpected');
      analytics.captureException(e, st, context: 'texturing');
      _upsert(
        base.copyWith(
          text: 'Failed to texture model. Please try again.',
          isStreaming: false,
        ),
        immediateRemote: true,
      );
    } finally {
      // Settlement moves the wallet (charge on success, hold release on
      // failure) — refresh so the UI shows it, mirroring paid generations.
      await _refreshWalletForTexture(request);
      // Allow re-texturing this model once the run settles (success or failure).
      _texturingSources.remove(sourceMessageId);
    }
  }

  // A start-phase failure message: same texture identity as [base] but with NO
  // workflowId, so resume never tries to poll a workflow that never launched.
  MessageModel _startFailureMessage(MessageModel base, String text) =>
      MessageModel(
        id: base.id,
        role: MessageRole.assistant,
        text: text,
        createdAt: base.createdAt,
        isStreaming: false,
        codeArtifact: base.codeArtifact,
        operation: 'texture_3d',
        messageType: 'texture',
        instructionPrompt: base.instructionPrompt,
      );

  // Resumes an in-progress texture message after a reload. Polls the same
  // workflow and passes the source code artifact (carried on the message) into
  // the finished result so the CODE / UV tabs keep working.
  Future<void> _resumeTexturing(MessageModel msg) async {
    final cad = ref.read(cadServiceProvider);
    final workflowId = msg.workflowId!;
    final code = msg.codeArtifact;
    try {
      final result = await cad.runTextureWorkflow(
        workflowId,
        startupGraceRetries: CadService.resumeStartupGraceRetries,
        onProgress: (status) => _publishWorkflowProgress(msg, status),
      );
      final failed = result.failed || result.glbUrl == null;
      _upsert(
        msg.copyWith(
          text: failed
              ? _failureText(result.errorMessage)
              : 'Your textured model is ready.',
          isStreaming: false,
          modelUrl: result.glbUrl,
          modelArtifact: result.modelArtifact,
          codeArtifact: code,
          sourceModelUrl: result.glbUrl,
          textureAssets: result.assets.map((a) => a.toJson()).toList(),
        ),
        immediateRemote: true,
      );
    } on CadException catch (e) {
      _upsert(
        msg.copyWith(text: _failureText(e.message), isStreaming: false),
        immediateRemote: true,
      );
    } catch (_) {
      _upsert(
        msg.copyWith(
          text: 'Failed to texture model. Please try again.',
          isStreaming: false,
        ),
        immediateRemote: true,
      );
    }
  }

  void _upsert(MessageModel msg, {bool immediateRemote = false}) {
    final current = _messages;
    final idx = current.indexWhere((m) => m.id == msg.id);
    final updated = [...current];
    if (idx == -1) {
      updated.add(msg);
    } else {
      updated[idx] = msg;
    }
    state = AsyncValue.data(ChatMessagesState(messages: updated, loaded: true));
    _save(updated, immediateRemote: immediateRemote);
  }
}

final messagesProvider = AsyncNotifierProvider.autoDispose
    .family<MessagesNotifier, ChatMessagesState, String>(MessagesNotifier.new);
