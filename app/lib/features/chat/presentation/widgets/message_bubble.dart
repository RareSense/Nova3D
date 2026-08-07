import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/api_keys/state/api_key_provider.dart';
import 'package:nova3d_frontend/features/cad/models/asset_version.dart';
import 'package:nova3d_frontend/features/cad/models/texture_request.dart';
import 'package:nova3d_frontend/features/cad/models/texture_result.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/features/chat/presentation/widgets/generation_progress_card.dart';
import 'package:nova3d_frontend/features/chat/presentation/widgets/magic_texture_dialog.dart';
import 'package:nova3d_frontend/features/chat/state/chat_provider.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';
import 'package:nova3d_frontend/shared/services/viewer_pointer_guard.dart';
import 'package:nova3d_frontend/shared/widgets/generation_preview.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onDelete,
    this.conversationId,
    this.assetVersions = const [],
    this.onOpenSidePanel,
  });
  final MessageModel message;
  final VoidCallback? onRetry;

  /// Soft-deletes this message (hidden everywhere, kept in the DB). Null hides
  /// the affordance (pending previews, streaming messages).
  final VoidCallback? onDelete;
  final String? conversationId;
  final List<AssetVersion> assetVersions;
  final VoidCallback? onOpenSidePanel;

  bool get _isUser => message.role == MessageRole.user;

  bool get _isTextureMessage =>
      message.operation == 'texture_3d' || message.messageType == 'texture';

  // Magic Texture is offered only on an ORIGINAL generation window that still
  // carries both source artifacts — never on an AI-edited, articulated, or
  // already-textured message (those have a non-initial [operation]).
  bool _canTexture(String? conversationId) =>
      conversationId != null &&
      (message.operation == null ||
          message.operation == 'initial_generation') &&
      message.modelArtifact != null &&
      message.codeArtifact != null;

  Future<void> _startMagicTexture(
    BuildContext context,
    WidgetRef ref,
    MessageModel message,
    String conversationId,
  ) async {
    // Capture the notifier before any await so we never touch a disposed ref.
    final notifier = ref.read(messagesProvider(conversationId).notifier);
    final savedKeys = await ref.read(apiKeyServiceProvider).loadValidKeys();
    if (!context.mounted) return;
    // The viewer iframe swallows pointer events across its region on web, which
    // would make the dialog's controls unresponsive where they overlap it.
    // Disable iframe pointer capture for the dialog's lifetime.
    setViewerIframesInteractive(false);
    final TextureRequest? request;
    try {
      request = await showDialog<TextureRequest>(
        context: context,
        builder: (_) =>
            MagicTextureDialog(initialGeminiKey: savedKeys['gemini'] ?? ''),
      );
    } finally {
      setViewerIframesInteractive(true);
    }
    if (request == null) return;
    await notifier.startTexturing(sourceMessage: message, request: request);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editModelOptions =
        ref.watch(byokGenerationModelOptionsProvider).valueOrNull ?? const [];
    final currentVersion = assetVersions.isNotEmpty ? assetVersions.last : null;

    return _DeletableRegion(
      onDelete: onDelete,
      alignEnd: _isUser,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: _isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!_isUser) ...[_Avatar(isUser: false), const SizedBox(width: 10)],
          Flexible(
            child: Column(
              crossAxisAlignment: _isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (_isUser && _isTextureMessage) ...[
                  const _TextureRequestBadge(),
                  const SizedBox(height: 6),
                ],
                if (!_isUser && message.isStreaming)
                  GenerationProgressCard(
                    statusText: message.text,
                    title: _isTextureMessage ? 'texturing' : 'generating',
                    modelLabel: _isTextureMessage
                        ? 'Gemini'
                        : message.modelLabel,
                    progress: message.workflowProgress,
                    progressStep: message.workflowProgressStep,
                    progressTotalSteps: message.workflowProgressTotalSteps,
                    stageLabel: message.workflowStageLabel,
                  )
                else if (message.text.isNotEmpty)
                  _BubbleContent(message: message, isUser: _isUser),
                if (message.allImageDataUrls.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final dataUrl in message.allImageDataUrls)
                        _ImageThumbnail(dataUrl: dataUrl),
                    ],
                  ),
                ],
                if (!message.isStreaming && message.modelUrl != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: kViewerDefaultHeight,
                    child: GenerationPreview(
                      key: ValueKey(message.id),
                      src: currentVersion?.modelUrl ?? message.modelUrl!,
                      viewerStateKey: message.id,
                      modelArtifact:
                          currentVersion?.modelArtifact ??
                          message.modelArtifact,
                      codeArtifact:
                          currentVersion?.codeArtifact ?? message.codeArtifact,
                      jointsArtifact:
                          currentVersion?.jointsArtifact ??
                          message.jointsArtifact,
                      joints: currentVersion?.joints ?? message.joints,
                      instructionPrompt: message.instructionPrompt,
                      sourceWorkflowId:
                          currentVersion?.workflowId ?? message.workflowId,
                      conversationId: conversationId,
                      assetVersions: assetVersions,
                      editModelOptions: editModelOptions,
                      defaultEditModelOptionId: message.modelOptionId,
                      onEditCompleted: conversationId != null
                          ? (completion) {
                              ref
                                  .read(
                                    messagesProvider(conversationId!).notifier,
                                  )
                                  .appendAiEditResult(completion);
                            }
                          : null,
                      onOpenSidePanel: onOpenSidePanel,
                      onMagicTexture: _canTexture(conversationId)
                          ? () => _startMagicTexture(
                              context,
                              ref,
                              message,
                              conversationId!,
                            )
                          : null,
                      textureAssets: message.textureAssets
                          .map(TextureAsset.fromJson)
                          .toList(),
                    ),
                  ),
                ],
                if (!message.isStreaming && onRetry != null) ...[
                  const SizedBox(height: 8),
                  _RetryButton(onRetry: onRetry!),
                ],
                if (!_isUser && message.workflowId != null) ...[
                  const SizedBox(height: 6),
                  _WorkflowIdBadge(
                    workflowId: message.workflowId!,
                    modelLabel: message.modelLabel,
                  ),
                ],
                if (!message.isStreaming) ...[
                  const SizedBox(height: 4),
                  _Timestamp(message.createdAt),
                ],
              ],
            ),
          ),
          if (_isUser) ...[const SizedBox(width: 10), _Avatar(isUser: true)],
        ],
      ),
      ),
    );
  }
}
/// Hover-revealed (desktop) / long-press (touch) delete for one message.
/// Deleting soft-deletes: the message disappears from the chat but stays in
/// the database. Confirmation guards against slips; the viewer iframes are
/// made non-interactive for the dialog's lifetime (they swallow pointer
/// events where they overlap it on web).
class _DeletableRegion extends StatefulWidget {
  const _DeletableRegion({
    required this.child,
    required this.alignEnd,
    this.onDelete,
  });

  final Widget child;
  final bool alignEnd;
  final VoidCallback? onDelete;

  @override
  State<_DeletableRegion> createState() => _DeletableRegionState();
}

class _DeletableRegionState extends State<_DeletableRegion> {
  bool _hovered = false;

  Future<void> _confirmDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    setViewerIframesInteractive(false);
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: kCream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: kInk, width: 1.5),
          ),
          title: const Text(
            'Delete this message?',
            style: TextStyle(color: kInk, fontSize: 16),
          ),
          content: const Text(
            'It will disappear from this chat. This cannot be undone.',
            style: TextStyle(color: kInkSoft, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: kInkSoft)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFD84C6F)),
              ),
            ),
          ],
        ),
      );
    } finally {
      setViewerIframesInteractive(true);
    }
    if (confirmed == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onDelete == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onLongPress: _confirmDelete,
        child: Stack(
          children: [
            widget.child,
            Positioned(
              top: 0,
              left: widget.alignEnd ? 0 : null,
              right: widget.alignEnd ? null : 0,
              child: AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: Tooltip(
                    message: 'Delete message',
                    child: InkWell(
                      onTap: _confirmDelete,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: kCream,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: kInk, width: 1),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: kInkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleContent extends StatefulWidget {
  const _BubbleContent({required this.message, required this.isUser});
  final MessageModel message;
  final bool isUser;

  @override
  State<_BubbleContent> createState() => _BubbleContentState();
}

class _BubbleContentState extends State<_BubbleContent> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isUser ? kLilacBg : kMintBg;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(widget.isUser ? 14 : 4),
      bottomRight: Radius.circular(widget.isUser ? 4 : 14),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(maxWidth: kBubbleMaxWidth),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(color: kInk, width: 1.5),
              boxShadow: const [
                BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
              ],
            ),
            child: widget.message.isStreaming && widget.message.text.isEmpty
                ? const _TypingIndicator()
                : SelectableText(
                    widget.message.text,
                    style: GoogleFonts.inter(
                      color: kInk,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
          ),
          if (_hovering && !widget.isUser && !widget.message.isStreaming)
            Positioned(
              right: -36,
              top: 4,
              child: _CopyButton(widget.message.text),
            ),
        ],
      ),
    );
  }
}

class _WorkflowIdBadge extends StatelessWidget {
  const _WorkflowIdBadge({required this.workflowId, this.modelLabel});
  final String workflowId;
  final String? modelLabel;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: kBubbleMaxWidth),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SelectableText(
            modelLabel == null || modelLabel!.isEmpty
                ? 'WF $workflowId'
                : 'WF $workflowId · $modelLabel',
            style: kSilkscreen(9, color: kInkMuted, letterSpacing: 0.4),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Copy workflow id',
          child: IconButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: workflowId)),
            icon: const Icon(Icons.copy, size: 14),
            color: kInkMuted,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
        ),
      ],
    ),
  );
}

class _CopyButton extends StatelessWidget {
  const _CopyButton(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Copy',
    child: InkWell(
      onTap: () => Clipboard.setData(ClipboardData(text: text)),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kInk, width: 1.5),
          boxShadow: const [
            BoxShadow(color: kInk, offset: Offset(1, 1), blurRadius: 0),
          ],
        ),
        child: const Icon(Icons.copy, size: 14, color: kInkSoft),
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.isUser});
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    if (!isUser) return const NovaCube(size: 32);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: kPinkBg,
        shape: BoxShape.circle,
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: const [
          BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
        ],
      ),
      child: const Center(
        child: Text(
          '✦',
          style: TextStyle(color: kPink, fontSize: 14, height: 1),
        ),
      ),
    );
  }
}

class _Timestamp extends StatelessWidget {
  const _Timestamp(this.time);
  final DateTime time;

  @override
  Widget build(BuildContext context) => Text(
    _formatTime(time),
    style: kSilkscreen(9, color: kInkMuted, letterSpacing: 0.4),
  );

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.dataUrl});
  final String dataUrl;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kInk, width: 1.5),
      boxShadow: const [
        BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8.5),
      child: Image.network(
        dataUrl,
        width: 150,
        height: 120,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    ),
  );
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: GestureDetector(
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kInk, width: 1.5),
          boxShadow: const [
            BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh, size: 14, color: kInkSoft),
            const SizedBox(width: 6),
            Text('RETRY', style: kSilkscreen(10, color: kInk)),
          ],
        ),
      ),
    ),
  );
}

class _TextureRequestBadge extends StatelessWidget {
  const _TextureRequestBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: kLilacBg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: kInk, width: 1.5),
      boxShadow: const [
        BoxShadow(color: kInk, offset: Offset(1, 1), blurRadius: 0),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('✨', style: TextStyle(fontSize: 10, height: 1)),
        const SizedBox(width: 4),
        Text(
          'TEXTURE REQUEST',
          style: kSilkscreen(8, color: kInk, letterSpacing: 0.4),
        ),
      ],
    ),
  );
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final delay = i / 3;
        final t = (_ctrl.value - delay).clamp(0.0, 1.0);
        final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Opacity(
            opacity: opacity,
            child: CircleAvatar(radius: 4, backgroundColor: kInkSoft),
          ),
        );
      }),
    ),
  );
}

