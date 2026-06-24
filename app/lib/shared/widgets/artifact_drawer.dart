import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';
import 'package:nova3d_frontend/shared/widgets/code_preview.dart';

class ArtifactDrawer extends StatelessWidget {
  const ArtifactDrawer({
    super.key,
    required this.message,
    required this.onClose,
    this.editModelOptions = const [],
    this.onArticulationCompleted,
  });

  final MessageModel message;
  final VoidCallback onClose;
  final List<GenerationModelOption> editModelOptions;
  // kept for API symmetry with StudioOverlay — not used in code-only drawer
  final void Function(
    String glbUrl,
    String workflowId,
    Map<String, dynamic>? jointsArtifact,
    List<Map<String, dynamic>> joints,
  )? onArticulationCompleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 580,
      decoration: const BoxDecoration(
        color: kCream,
        border: Border(left: BorderSide(color: kInk, width: 1.5)),
      ),
      child: Column(
        children: [
          _DrawerHeader(onClose: onClose),
          Expanded(
            child: message.codeArtifact != null
                ? CodePreview(codeArtifact: message.codeArtifact!)
                : const Center(
                    child: Text(
                      'No code artifact',
                      style: TextStyle(color: kInkMuted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: kCream,
        border: Border(bottom: BorderSide(color: kLineSoft, width: 1.5)),
      ),
      child: Row(
        children: [
          const Text(
            '</>',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              color: kPink,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text('CODE', style: kSilkscreen(10, color: kInk, letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: kButterBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: kInk, width: 1),
            ),
            child: Text('PY', style: kSilkscreen(8, color: kInk, letterSpacing: 0.4)),
          ),
          const Spacer(),
          InkWell(
            onTap: onClose,
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
              child: const Icon(Icons.close, size: 14, color: kInk),
            ),
          ),
        ],
      ),
    );
  }
}
