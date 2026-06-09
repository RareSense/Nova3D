import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/asset_version.dart';
import 'package:nova3d_frontend/features/cad/models/cad_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';
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
  final repo = ConversationRepository(
    ref.watch(conversationLocalSourceProvider),
    ref.watch(chatServiceProvider),
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

    final local = await ref.read(conversationRepositoryProvider).load();
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
    try {
      final synced = await ref
          .read(conversationRepositoryProvider)
          .syncLatest();
      // Guard against a user switch that completed while the fetch was in
      // flight — don't overwrite the new user's state with stale data.
      if (ref.read(authProvider).valueOrNull?.id != userId) return;
      // Pre-seed local message cache from the snapshot data already embedded
      // in each conversation so that opening one is instant without an extra
      // API call. Fire-and-forget; non-fatal if it fails.
      unawaited(ref.read(messageLocalSourceProvider).seedFromSnapshots(synced));
      state = AsyncValue.data(synced);
    } catch (_) {
      // Local cache remains authoritative for rendering when remote history
      // sync is temporarily unavailable.
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
        byId[message.id] = message;
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
          a[i].sourceModelUrl != b[i].sourceModelUrl) {
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
              m.workflowId != null &&
              m.workflowId!.isNotEmpty &&
              m.modelUrl == null,
        )
        .toList();
    for (final msg in active) {
      final workflowId = msg.workflowId!;
      _upsert(
        msg.copyWith(
          text: 'Checking generation status...',
          isStreaming: true,
          clearRetryRequest: true,
        ),
      );
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
          imageDataUrl: request.imageDataUrl,
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
          imageDataUrl: request.imageDataUrl,
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
    try {
      await _ensurePaidCreditBudget(request, cad);
      final startedWorkflowId = await cad.startGeneration(
        request,
        workflowId: workflowId,
        conversationId: arg,
      );
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
    } catch (_) {
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
  }) {
    return cad.runWorkflow(
      workflowId,
      onProgress: (status) => _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: status.progressLabel,
          createdAt: assistantCreatedAt,
          isStreaming: true,
          workflowId: workflowId,
          modelOptionId: modelOptionId,
          modelLabel: modelLabel,
        ),
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
    final wallet = await ref.read(billingProvider.notifier).refreshWallet();
    final available =
        wallet?.available ?? ref.read(billingProvider).wallet?.available;
    if (available == null) {
      throw CadException(
        'Nova3D could not confirm your credit balance. Refresh credits or open /subscription, then try again.',
      );
    }
    if (available < required) {
      throw CadException(_insufficientCreditsText(required, available));
    }
  }

  Future<void> _refreshWalletForPaid(GenerationRequest request) async {
    if (!request.modelOption.isPaidCredit) return;
    await ref.read(billingProvider.notifier).refreshWallet();
  }

  String _insufficientCreditsText(int required, int available) =>
      'This model needs $required credits, but you have $available available. Buy more credits at /subscription and try again.';

  Future<void> retry(String failedMessageId) async {
    if (_busy) return;
    final msg = _messages.firstWhere(
      (m) => m.id == failedMessageId,
      orElse: () => throw StateError('message not found'),
    );
    if (msg.retryRequest == null) return;
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
