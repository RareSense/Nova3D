import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/features/cad/models/generation_request.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/features/chat/presentation/widgets/chat_input.dart';
import 'package:nova3d_frontend/features/chat/presentation/widgets/message_bubble.dart';
import 'package:nova3d_frontend/features/chat/state/chat_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollCtrl = ScrollController();
  String? _selectedModelId;

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
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

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
    final isStreaming = messages.any((m) => m.isStreaming);
    final pendingDraft = ref.watch(
      generationDraftsProvider,
    )[widget.conversationId];
    final modelOptions = ref.watch(generationModelOptionsProvider);
    final availableOptions = modelOptions.valueOrNull ?? const [];

    final selectedModel = GenerationModelOption.findById(
      availableOptions,
      _selectedModelId,
    );
    if (selectedModel != null && selectedModel.id != _selectedModelId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedModelId = selectedModel.id);
      });
    }

    ref.listen(messagesProvider(widget.conversationId), (_, _) {
      _scrollToBottom();
    });

    return Column(
      children: [
        Expanded(child: _buildBody(messagesAsync, messages, pendingDraft)),

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
  }

  Widget _buildBody(
    AsyncValue<ChatMessagesState> messagesAsync,
    List<MessageModel> messages,
    GenerationRequest? pendingDraft,
  ) {
    if (messagesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator(color: kLilac));
    }

    if (messages.isEmpty && pendingDraft != null) {
      return _PendingView(draft: pendingDraft);
    }

    if (messages.isEmpty) {
      return _EmptyState();
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (_, i) => _CenteredMessage(
        child: MessageBubble(
          message: messages[i],
          conversationId: widget.conversationId,
          onRetry: messages[i].retryRequest != null
              ? () => ref
                    .read(messagesProvider(widget.conversationId).notifier)
                    .retry(messages[i].id)
              : null,
        ),
      ),
    );
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
            imageDataUrl: draft.imageDataUrl,
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
  const _CenteredMessage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: kContentMaxWidth),
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
