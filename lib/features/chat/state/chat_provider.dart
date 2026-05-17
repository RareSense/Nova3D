import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova3d_frontend/features/auth/state/auth_provider.dart';
import 'package:nova3d_frontend/features/cad/data/cad_service.dart';
import 'package:nova3d_frontend/features/cad/models/cad_models.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/features/chat/data/chat_service.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

const _kConversationsKey = 'local_conversations';
const _kMessagesPrefix = 'local_messages_';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref.watch(authServiceProvider));
});

// ── Conversations ─────────────────────────────────────────────────────────────

class ConversationsNotifier
    extends StateNotifier<AsyncValue<List<ConversationModel>>> {
  ConversationsNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    final persisted = await _loadConvsFromPrefs();
    state = AsyncValue.data(persisted);
  }

  void prepend(ConversationModel conv) {
    final updated = <ConversationModel>[conv, ...state.valueOrNull ?? []];
    state = AsyncValue.data(updated);
    _saveConvsToPrefs(updated);
  }

  void remove(String id) {
    final updated = (state.valueOrNull ?? []).where((c) => c.id != id).toList();
    state = AsyncValue.data(updated);
    _saveConvsToPrefs(updated);
    _deleteMessagesFromPrefs(id);
  }

  static Future<List<ConversationModel>> _loadConvsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kConversationsKey);
      if (raw == null) return [];
      final list = (json.decode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      return list.map(ConversationModel.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveConvsToPrefs(List<ConversationModel> convs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kConversationsKey,
        json.encode(convs.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<void> _deleteMessagesFromPrefs(String convId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kMessagesPrefix$convId');
    } catch (_) {}
  }
}

final conversationsProvider =
    StateNotifierProvider<
      ConversationsNotifier,
      AsyncValue<List<ConversationModel>>
    >((_) => ConversationsNotifier());

// ── Generation draft ──────────────────────────────────────────────────────────

class GenerationDraftsNotifier
    extends StateNotifier<Map<String, GenerationRequest>> {
  GenerationDraftsNotifier() : super({});

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
    StateNotifierProvider<
      GenerationDraftsNotifier,
      Map<String, GenerationRequest>
    >((_) => GenerationDraftsNotifier());

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

class MessagesNotifier extends StateNotifier<ChatMessagesState> {
  final CadService _cad;
  final String conversationId;
  bool _busy = false;

  MessagesNotifier(this._cad, this.conversationId)
    : super(const ChatMessagesState(messages: [])) {
    _loadFromPrefs();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_kMessagesPrefix$conversationId');
      if (raw == null || state.messages.isNotEmpty) {
        state = state.copyWith(loaded: true);
        return;
      }
      final list = json.decode(raw) as List<dynamic>;
      final msgs = list
          .map((e) => MessageModel.fromLocalJson(e as Map<String, dynamic>))
          .toList();
      if (state.messages.isEmpty) {
        state = ChatMessagesState(messages: msgs, loaded: true);
        _resumeActiveGenerations();
      }
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> _saveToPrefs(List<MessageModel> msgs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_kMessagesPrefix$conversationId',
        json.encode(msgs.map((m) => m.toLocalJson()).toList()),
      );
    } catch (_) {}
  }

  void _resumeActiveGenerations() {
    final active = state.messages
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
      _saveToPrefs(state.messages);
      _busy = true;
      _pollExistingGeneration(
        workflowId: workflowId,
        assistantId: msg.id,
        assistantCreatedAt: msg.createdAt,
      );
    }
  }

  // ── Optimistic seed ────────────────────────────────────────────────────────

  void seed(GenerationRequest request) {
    if (_busy || state.messages.isNotEmpty) return;
    final now = DateTime.now();
    state = ChatMessagesState(
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
    _saveToPrefs(state.messages);
  }

  // ── Generation ─────────────────────────────────────────────────────────────

  Future<void> sendGeneration(GenerationRequest request) async {
    if (_busy) return;
    if (!request.hasText && !request.hasImage) return;
    _busy = true;

    final now = DateTime.now();

    String userId;
    String assistantId;
    DateTime assistantCreatedAt;
    final workflowId = CadService.createWorkflowId();

    if (state.messages.isNotEmpty && state.messages.any((m) => m.isStreaming)) {
      // Already seeded — reuse those IDs for upserts.
      final seededUser = state.messages.firstWhere(
        (m) => m.role == MessageRole.user,
      );
      final seededAssistant = state.messages.firstWhere(
        (m) => m.role == MessageRole.assistant,
      );
      userId = seededUser.id;
      assistantId = seededAssistant.id;
      assistantCreatedAt = seededAssistant.createdAt;
      state = ChatMessagesState(
        messages: [
          seededUser.copyWith(text: request.prompt),
          seededAssistant.copyWith(
            text: 'Starting generation…',
            isStreaming: true,
            workflowId: workflowId,
          ),
        ],
        loaded: true,
      );
    } else {
      userId = 'user-${now.millisecondsSinceEpoch}';
      assistantId = 'cad-${now.millisecondsSinceEpoch}';
      assistantCreatedAt = now;
      state = state.copyWith(
        messages: [
          ...state.messages,
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
        ],
        loaded: true,
      );
    }
    _saveToPrefs(state.messages);

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
    try {
      final startedWorkflowId = await _cad.startGeneration(
        request,
        workflowId: workflowId,
      );
      _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: 'Generating your 3D model...',
          createdAt: assistantCreatedAt,
          isStreaming: true,
          workflowId: startedWorkflowId,
        ),
      );
      _saveToPrefs(state.messages);

      final result = await _runWorkflowWithProgress(
        startedWorkflowId,
        assistantId: assistantId,
        assistantCreatedAt: assistantCreatedAt,
      );

      final failed = result.failed || result.glbUrl == null;
      final msg = MessageModel(
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
        modelOptionId: request.modelOption.id,
        instructionPrompt: request.prompt.trim(),
        retryRequest: failed ? request : null,
      );
      _upsert(msg);
      _saveToPrefs(state.messages);
    } on CadException catch (e) {
      final msg = MessageModel(
        id: assistantId,
        role: MessageRole.assistant,
        text: _failureText(e.message),
        createdAt: assistantCreatedAt,
        isStreaming: false,
        workflowId: workflowId,
        retryRequest: request,
      );
      _upsert(msg);
      _saveToPrefs(state.messages);
    } catch (_) {
      final msg = MessageModel(
        id: assistantId,
        role: MessageRole.assistant,
        text: 'Failed to generate model. Please try again.',
        createdAt: assistantCreatedAt,
        isStreaming: false,
        workflowId: workflowId,
        retryRequest: request,
      );
      _upsert(msg);
      _saveToPrefs(state.messages);
    } finally {
      _busy = false;
    }
  }

  Future<CadResult> _runWorkflowWithProgress(
    String workflowId, {
    required String assistantId,
    required DateTime assistantCreatedAt,
  }) {
    return _cad.runWorkflow(
      workflowId,
      onProgress: (status) => _upsert(
        MessageModel(
          id: assistantId,
          role: MessageRole.assistant,
          text: status.progressLabel,
          createdAt: assistantCreatedAt,
          isStreaming: true,
          workflowId: workflowId,
        ),
      ),
    );
  }

  Future<void> _pollExistingGeneration({
    required String workflowId,
    required String assistantId,
    required DateTime assistantCreatedAt,
  }) async {
    try {
      final result = await _runWorkflowWithProgress(
        workflowId,
        assistantId: assistantId,
        assistantCreatedAt: assistantCreatedAt,
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
        ),
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
        ),
      );
    } finally {
      _busy = false;
      _saveToPrefs(state.messages);
    }
  }

  Future<void> retry(String failedMessageId) async {
    if (_busy) return;
    final msg = state.messages.firstWhere(
      (m) => m.id == failedMessageId,
      orElse: () => throw StateError('not found'),
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
    _saveToPrefs(state.messages);
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

  void _upsert(MessageModel msg) {
    final messages = state.messages;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx == -1) {
      state = state.copyWith(messages: [...messages, msg], loaded: true);
    } else {
      final updated = [...messages];
      updated[idx] = msg;
      state = state.copyWith(messages: updated, loaded: true);
    }
    _saveToPrefs(state.messages);
  }
}

final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, ChatMessagesState, String>((
      ref,
      convId,
    ) {
      return MessagesNotifier(ref.watch(cadServiceProvider), convId);
    });
