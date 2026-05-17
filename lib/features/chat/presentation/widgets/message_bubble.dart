import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/state/cad_provider.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';
import 'package:nova3d_frontend/shared/widgets/glb_viewer.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({super.key, required this.message, this.onRetry});
  final MessageModel message;
  final VoidCallback? onRetry;

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
                if (message.text.isNotEmpty)
                  _BubbleContent(message: message, isUser: _isUser),
                if (message.imageDataUrl != null) ...[
                  const SizedBox(height: 6),
                  _ImageThumbnail(dataUrl: message.imageDataUrl!),
                ],
                if (!message.isStreaming && message.modelUrl != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 400,
                    child: GlbViewer(
                      key: ValueKey(message.id),
                      src: message.modelUrl!,
                      modelArtifact: message.modelArtifact,
                      codeArtifact: message.codeArtifact,
                      jointsArtifact: message.jointsArtifact,
                      joints: message.joints,
                      instructionPrompt: message.instructionPrompt,
                      sourceWorkflowId: message.workflowId,
                      editModelOptions: editModelOptions,
                      defaultEditModelOptionId: message.modelOptionId,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: const BoxConstraints(maxWidth: 640),
            decoration: BoxDecoration(
              color: widget.isUser ? kAccentBlue : kBgTertiary,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(widget.isUser ? 16 : 4),
                bottomRight: Radius.circular(widget.isUser ? 4 : 16),
              ),
            ),
            child: widget.message.isStreaming && widget.message.text.isEmpty
                ? const _TypingIndicator()
                : SelectableText(
                    widget.message.text,
                    style: TextStyle(
                      color: widget.isUser ? Colors.white : kTextPrimary,
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
    constraints: const BoxConstraints(maxWidth: 640),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SelectableText(
            'WF $workflowId',
            style: const TextStyle(
              color: kTextMuted,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Copy workflow id',
          child: IconButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: workflowId)),
            icon: const Icon(Icons.copy, size: 14),
            color: kTextMuted,
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
          color: kBgTertiary,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kBorderColor),
        ),
        child: const Icon(Icons.copy, size: 14, color: kTextSecondary),
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.isUser});
  final bool isUser;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: isUser ? kAccentBlue.withValues(alpha: 0.2) : kBgTertiary,
      shape: BoxShape.circle,
      border: Border.all(color: kBorderColor),
    ),
    child: Center(
      child: Icon(
        isUser ? Icons.person : Icons.auto_awesome,
        size: 16,
        color: isUser ? kAccentBlue : kTextSecondary,
      ),
    ),
  );
}

class _Timestamp extends StatelessWidget {
  const _Timestamp(this.time);
  final DateTime time;

  @override
  Widget build(BuildContext context) => Text(
    _formatTime(time),
    style: const TextStyle(color: kTextMuted, fontSize: 11),
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
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.network(
      dataUrl,
      height: 160,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    ),
  );
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh, size: 14),
      label: const Text('Retry', style: TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: kTextSecondary,
        side: const BorderSide(color: kBorderColor),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    builder: (_, _) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i / 3;
          final t = (_ctrl.value - delay).clamp(0.0, 1.0);
          final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Opacity(
              opacity: opacity,
              child: const CircleAvatar(
                radius: 4,
                backgroundColor: kTextSecondary,
              ),
            ),
          );
        }),
      );
    },
  );
}
