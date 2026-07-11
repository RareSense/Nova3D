import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/asset_version.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/features/chat/presentation/widgets/message_bubble.dart';
import 'package:nova3d_frontend/features/chat/state/chat_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';
import 'package:nova3d_frontend/shared/widgets/artifact_drawer.dart';

enum _PanelMode { none, side }

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollCtrl = ScrollController();
  String? _selectedModelId;
  _PanelMode _panelMode = _PanelMode.none;
  MessageModel? _panelMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final draft = ref
          .read(generationDraftsProvider.notifier)
          .take(widget.conversationId);
      if (draft != null) {
        ref
            .read(messagesProvider(widget.conversationId).notifier)
            .sendGeneration(draft);
        return;
      }
      // A showcase-originated texture run handed off as a draft: start it once,
      // here, so the messages provider stays alive under this page.
      final textureDraft = ref
          .read(textureDraftsProvider.notifier)
          .take(widget.conversationId);
      if (textureDraft != null) {
        ref
            .read(messagesProvider(widget.conversationId).notifier)
            .startTexturingFromArtifacts(
              request: textureDraft.request,
              glbArtifact: textureDraft.glbArtifact,
              codeArtifact: textureDraft.codeArtifact,
              sourceId: textureDraft.sourceId,
            );
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _openSidePanel(MessageModel message) => setState(() {
    _panelMode = _PanelMode.side;
    _panelMessage = message;
  });

  void _closePanel() => setState(() {
    _panelMode = _PanelMode.none;
    _panelMessage = null;
  });

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));
    final messages = messagesAsync.valueOrNull?.messages ?? const [];
    final pendingDraft = ref.watch(
      generationDraftsProvider,
    )[widget.conversationId];
    final modelOptions = ref.watch(generationModelOptionsProvider);
    final editModelOptions = ref.watch(byokGenerationModelOptionsProvider);
    final availableOptions = modelOptions.valueOrNull ?? const [];
    final availableEditOptions = editModelOptions.valueOrNull ?? const [];

    final selectedModel = GenerationModelOption.findById(
      availableOptions,
      _selectedModelId,
    );
    if (selectedModel != null && selectedModel.id != _selectedModelId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedModelId = selectedModel.id);
      });
    }

    // Auto-scroll only when a NEW message is appended — not on every progress
    // tick. Scrolling on each 3s poll update yanked the user down whenever they
    // scrolled up to inspect an earlier model.
    ref.listen(messagesProvider(widget.conversationId), (prev, next) {
      final prevCount = prev?.valueOrNull?.messages.length ?? 0;
      final nextCount = next.valueOrNull?.messages.length ?? 0;
      if (nextCount > prevCount) _scrollToBottom();
    });

    final chatColumn = Column(
      children: [
        Expanded(
          child: _buildBody(
            messagesAsync,
            messages,
            pendingDraft,
            availableOptions,
            narrowColumn: _panelMode == _PanelMode.side,
          ),
        ),
        // Conversations are single-turn: once a generation exists, lock the
        // input and prompt the user to start a new conversation instead.
        // if (messages.any((m) => m.role == MessageRole.assistant))
        const _NewCreationBar(),
        // else
        //   ChatInput(
        //     modelOptions: availableOptions,
        //     selectedModel: selectedModel,
        //     onModelChanged: (option) =>
        //         setState(() => _selectedModelId = option?.id),
        //     disabled: messagesAsync.isLoading || isStreaming,
        //     onSend: (request) async {
        //       await ref
        //           .read(messagesProvider(widget.conversationId).notifier)
        //           .sendGeneration(request);
        //       return true;
        //     },
        //   ),
      ],
    );

    if (_panelMode == _PanelMode.side) {
      return Row(
        children: [
          Expanded(child: chatColumn),
          ArtifactDrawer(
            message: _panelMessage!,
            onClose: _closePanel,
            editModelOptions: availableEditOptions,
            onArticulationCompleted:
                (glbUrl, workflowId, jointsArtifact, joints) => ref
                    .read(messagesProvider(widget.conversationId).notifier)
                    .patchArticulation(
                      _panelMessage!.id,
                      modelUrl: glbUrl,
                      workflowId: workflowId,
                      jointsArtifact: jointsArtifact,
                      joints: joints,
                    ),
          ),
        ],
      );
    }

    return chatColumn;
  }

  Widget _buildBody(
    AsyncValue<ChatMessagesState> messagesAsync,
    List<MessageModel> messages,
    GenerationRequest? pendingDraft,
    List<GenerationModelOption> availableOptions, {
    required bool narrowColumn,
  }) {
    if (messagesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: kLilac));
    }

    if (messages.isEmpty && pendingDraft != null) {
      return _PendingView(draft: pendingDraft);
    }

    if (messages.isEmpty) {
      return _EmptyState();
    }

    final visibleMessages = _visibleMessages(messages);
    final assetVersions = _assetVersionsForConversation(messages);
    final maxWidth = narrowColumn ? 460.0 : kContentMaxWidth;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: visibleMessages.length,
      itemBuilder: (_, i) {
        final message = visibleMessages[i];
        // Key by message id so the list matches elements by identity, not
        // index. This keeps each preview's platform view (iframe) bound to its
        // own message across inserts/reorders instead of being recycled — the
        // recycling is what flashed previous previews black on every rebuild.
        return _CenteredMessage(
          key: ValueKey(message.id),
          maxWidth: maxWidth,
          child: MessageBubble(
            message: message,
            conversationId: widget.conversationId,
            assetVersions: _isInitialModelMessage(message)
                ? assetVersions
                : const [],
            onRetry: message.retryRequest != null
                ? () => ref
                      .read(messagesProvider(widget.conversationId).notifier)
                      .retry(message.id)
                : null,
            onDelete: message.isStreaming
                ? null
                : () => ref
                      .read(messagesProvider(widget.conversationId).notifier)
                      .deleteMessage(message.id),
            onOpenSidePanel: !narrowColumn && message.codeArtifact != null
                ? () => _openSidePanel(message)
                : null,
          ),
        );
      },
    );
  }

  List<MessageModel> _visibleMessages(List<MessageModel> messages) => messages
      .where(
        (message) =>
            !message.isDeleted &&
            (!_isPersistedAiEditVersion(message) || message.isStreaming),
      )
      .toList(growable: false);

  bool _isInitialModelMessage(MessageModel message) =>
      message.role == MessageRole.assistant &&
      message.modelUrl != null &&
      (message.operation == null || message.operation == 'initial_generation');

  bool _isPersistedAiEditVersion(MessageModel message) =>
      message.role == MessageRole.assistant &&
      message.modelUrl != null &&
      message.workflowId != null &&
      message.isAssetVersionEvent &&
      message.operation != 'initial_generation';

  List<AssetVersion> _assetVersionsForConversation(
    List<MessageModel> messages,
  ) {
    final versions = <AssetVersion>[];
    for (final message in messages) {
      final modelUrl = message.modelUrl;
      final workflowId = message.workflowId;
      if (message.role != MessageRole.assistant ||
          message.isDeleted ||
          modelUrl == null ||
          modelUrl.isEmpty ||
          workflowId == null ||
          workflowId.isEmpty) {
        continue;
      }
      // Textured models are standalone messages with their own window, not
      // versions of the source generation — never fold them into its switcher.
      if (message.operation == 'texture_3d' ||
          message.messageType == 'texture') {
        continue;
      }
      versions.add(
        AssetVersion(
          messageId: message.id,
          label: message.text.isEmpty ? 'Model version' : message.text,
          operation: message.operation ?? 'generation',
          modelUrl: modelUrl,
          workflowId: workflowId,
          sourceModelUrl: message.sourceModelUrl ?? modelUrl,
          modelArtifact: message.modelArtifact,
          codeArtifact: message.codeArtifact,
          jointsArtifact: message.jointsArtifact,
          joints: message.joints,
        ),
      );
    }
    return versions;
  }
}

// ── Optimistic pending view ───────────────────────────────────────────────────

class _PendingView extends StatelessWidget {
  const _PendingView({required this.draft});
  final GenerationRequest draft;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    children: [
      _CenteredMessage(
        child: MessageBubble(
          message: MessageModel(
            id: '_pending_user',
            role: MessageRole.user,
            text: draft.prompt,
            createdAt: DateTime.now(),
            imageDataUrls: draft.imageDataUrls,
          ),
        ),
      ),
      _CenteredMessage(
        child: MessageBubble(
          message: MessageModel(
            id: '_pending_asst',
            role: MessageRole.assistant,
            text: 'Starting generation…',
            createdAt: DateTime.now(),
            isStreaming: true,
          ),
        ),
      ),
    ],
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    super.key,
    required this.child,
    this.maxWidth = kContentMaxWidth,
  });
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

// ── New creation redirect bar ─────────────────────────────────────────────────

class _NewCreationBar extends StatelessWidget {
  const _NewCreationBar();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: const BoxDecoration(
      color: kSurface,
      border: Border(top: BorderSide(color: kInk, width: 1.5)),
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Want to create something else?',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: kInkSoft, fontSize: 13),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.add, size: 15, color: kLilac),
              label: const Text(
                'Start a new 3D creation',
                style: TextStyle(color: kLilac, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: kLilacBg,
            shape: BoxShape.circle,
            border: Border.all(color: kInk, width: 1.5),
            boxShadow: const [
              BoxShadow(color: kInk, offset: Offset(3, 3), blurRadius: 0),
            ],
          ),
          child: const Center(
            child: Text('✦', style: TextStyle(color: kLilac, fontSize: 26)),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Start the conversation',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: kInk),
        ),
        const SizedBox(height: 8),
        Text(
          'Describe the 3D model you want to create.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
