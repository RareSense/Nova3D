import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/features/chat/presentation/widgets/generation_progress_card.dart';
import 'package:nova3d_frontend/features/chat/state/chat_provider.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';
import 'package:nova3d_frontend/shared/widgets/glb_viewer.dart';
import 'package:nova3d_frontend/shared/widgets/nova_cube.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.conversationId,
  });
  final MessageModel message;
  final VoidCallback? onRetry;
  final String? conversationId;

  bool get _isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editModelOptions =
        ref.watch(generationModelOptionsProvider).valueOrNull ?? const [];

    return Padding(
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
                if (!_isUser && message.isStreaming)
                  GenerationProgressCard(statusText: message.text)
                else if (message.text.isNotEmpty)
                  _BubbleContent(message: message, isUser: _isUser),
                if (message.imageDataUrl != null) ...[
                  const SizedBox(height: 6),
                  _ImageThumbnail(dataUrl: message.imageDataUrl!),
                ],
                if (!message.isStreaming && message.modelUrl != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: kViewerDefaultHeight,
                    child: GlbViewer(
                      key: ValueKey(message.id),
                      src: message.modelUrl!,
                      viewerStateKey: message.id,
                      modelArtifact: message.modelArtifact,
                      codeArtifact: message.codeArtifact,
                      jointsArtifact: message.jointsArtifact,
                      joints: message.joints,
                      instructionPrompt: message.instructionPrompt,
                      sourceWorkflowId: message.workflowId,
                      conversationId: conversationId,
                      editModelOptions: editModelOptions,
                      defaultEditModelOptionId: message.modelOptionId,
                      onArticulationCompleted: conversationId != null
                          ? (glbUrl, workflowId, jointsArtifact, joints) {
                              ref
                                  .read(
                                    messagesProvider(conversationId!).notifier,
                                  )
                                  .patchArticulation(
                                    message.id,
                                    modelUrl: glbUrl,
                                    workflowId: workflowId,
                                    jointsArtifact: jointsArtifact,
                                    joints: joints,
                                  );
                            }
                          : null,
                    ),
                  ),
                ],
                if (!message.isStreaming && onRetry != null) ...[
                  const SizedBox(height: 8),
                  _RetryButton(onRetry: onRetry!),
                ],
                if (!_isUser && message.workflowId != null) ...[
                  const SizedBox(height: 6),
                  _WorkflowIdBadge(workflowId: message.workflowId!),
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
  const _WorkflowIdBadge({required this.workflowId});
  final String workflowId;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: kBubbleMaxWidth),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SelectableText(
            'WF $workflowId',
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
        height: 160,
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
