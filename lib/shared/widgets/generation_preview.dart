import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/asset_version.dart';
import 'package:nova3d_frontend/features/cad/models/generation_model_option.dart';
import 'package:nova3d_frontend/shared/widgets/code_preview.dart';
import 'package:nova3d_frontend/shared/widgets/glb_viewer.dart';

/// Wraps [GlbViewer] with a header toolbar that toggles between the model
/// preview and a code preview of the generation's Python code artifact.
///
/// When no code artifact is available, falls back to a bare [GlbViewer]
/// (no header) — the toggle has nothing to switch to.
class GenerationPreview extends StatefulWidget {
  const GenerationPreview({
    super.key,
    required this.src,
    this.autoRotate = true,
    this.modelArtifact,
    this.codeArtifact,
    this.jointsArtifact,
    this.joints = const [],
    this.instructionPrompt,
    this.sourceWorkflowId,
    this.conversationId,
    this.assetVersions = const [],
    this.editModelOptions = const [],
    this.defaultEditModelOptionId,
    this.onArticulationCompleted,
    this.onEditCompleted,
    this.viewerStateKey,
    this.onOpenSidePanel,
  });

  final String src;
  final bool autoRotate;
  final Map<String, dynamic>? modelArtifact;
  final Map<String, dynamic>? codeArtifact;
  final Map<String, dynamic>? jointsArtifact;
  final List<Map<String, dynamic>> joints;
  final String? instructionPrompt;
  final String? sourceWorkflowId;
  final String? conversationId;
  final List<AssetVersion> assetVersions;
  final List<GenerationModelOption> editModelOptions;
  final String? defaultEditModelOptionId;
  final void Function(
    String glbUrl,
    String workflowId,
    Map<String, dynamic>? jointsArtifact,
    List<Map<String, dynamic>> joints,
  )?
  onArticulationCompleted;
  final void Function(AiEditCompletion completion)? onEditCompleted;
  final String? viewerStateKey;
  final VoidCallback? onOpenSidePanel;

  @override
  State<GenerationPreview> createState() => _GenerationPreviewState();
}

enum _PreviewTab { model, code }

class _GenerationPreviewState extends State<GenerationPreview> {
  _PreviewTab _tab = _PreviewTab.model;

  bool get _hasCode {
    final url = widget.codeArtifact?['url'];
    return url is String && url.isNotEmpty;
  }

  GlbViewer _buildGlbViewer() {
    return GlbViewer(
      src: widget.src,
      autoRotate: widget.autoRotate,
      modelArtifact: widget.modelArtifact,
      codeArtifact: widget.codeArtifact,
      jointsArtifact: widget.jointsArtifact,
      joints: widget.joints,
      instructionPrompt: widget.instructionPrompt,
      sourceWorkflowId: widget.sourceWorkflowId,
      conversationId: widget.conversationId,
      assetVersions: widget.assetVersions,
      editModelOptions: widget.editModelOptions,
      defaultEditModelOptionId: widget.defaultEditModelOptionId,
      onArticulationCompleted: widget.onArticulationCompleted,
      onEditCompleted: widget.onEditCompleted,
      viewerStateKey: widget.viewerStateKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCode) {
      // Nothing to toggle to — render the viewer unchanged.
      return _buildGlbViewer();
    }

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: const [
          BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _HeaderToolbar(
            active: _tab,
            onSelect: (t) => setState(() => _tab = t),
            modelMeta: _modelMeta(),
            codeMeta: _codeMeta(),
            onOpenSidePanel: widget.onOpenSidePanel,
          ),
          Expanded(
            child: Stack(
              children: [
                // CodePreview: always mounted so the fetched source survives
                // tab switches. Offstage (not Visibility) is used because it
                // genuinely removes the widget from the paint tree while
                // keeping its state alive — and it works correctly for pure
                // Flutter widgets like CodePreview.
                Positioned.fill(
                  child: Offstage(
                    offstage: _tab != _PreviewTab.code,
                    child: CodePreview(codeArtifact: widget.codeArtifact!),
                  ),
                ),
                // GlbViewer: only in the tree when the model tab is active.
                // HtmlElementView (the iframe) renders in a separate HTML
                // layer that ignores every Flutter visibility mechanism
                // (Offstage, IndexedStack, Opacity, Visibility, 0×0 collapse)
                // — especially after the browser Fullscreen API has been used.
                // Removing it from the widget tree is the only reliable fix.
                // viewerStateKey ties GlbViewer to IndexedDB, so camera
                // position and edit history survive the remount.
                if (_tab == _PreviewTab.model)
                  Positioned.fill(child: _buildGlbViewer()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _modelMeta() {
    final artifact = widget.modelArtifact;
    final ext = _extOf(widget.src) ?? 'glb';
    final size = _sizeLabel(artifact);
    return size == null ? ext.toUpperCase() : '${ext.toUpperCase()} · $size';
  }

  String _codeMeta() {
    final size = _sizeLabel(widget.codeArtifact);
    return size == null ? 'PY' : 'PY · $size';
  }
}

// ── Header toolbar with Model / Code tabs ────────────────────────────────────
class _HeaderToolbar extends StatelessWidget {
  const _HeaderToolbar({
    required this.active,
    required this.onSelect,
    required this.modelMeta,
    required this.codeMeta,
    this.onOpenSidePanel,
  });

  final _PreviewTab active;
  final ValueChanged<_PreviewTab> onSelect;
  final String modelMeta;
  final String codeMeta;
  final VoidCallback? onOpenSidePanel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: kCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: kLineSoft, width: 1.5)),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'MODEL',
            active: active == _PreviewTab.model,
            onTap: () => onSelect(_PreviewTab.model),
            icon: const Text(
              '◆',
              style: TextStyle(fontSize: 11, color: kLilac, height: 1),
            ),
          ),
          const SizedBox(width: 6),
          _Tab(
            label: 'CODE',
            active: active == _PreviewTab.code,
            onTap: () => onSelect(_PreviewTab.code),
            icon: const Text(
              '</>',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                color: kPink,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            hint: 'PY',
          ),
          const Spacer(),
          Text(
            active == _PreviewTab.model ? modelMeta : codeMeta,
            style: kSilkscreen(9, color: kInkMuted, letterSpacing: 0.5),
          ),
          if (onOpenSidePanel != null && active == _PreviewTab.code) ...[
            const SizedBox(width: 8),
            _EscalateButton(label: '⇲ SIDE', onTap: onOpenSidePanel!),
          ],
        ],
      ),
    );
  }
}

class _EscalateButton extends StatelessWidget {
  const _EscalateButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kInk, width: 1.5),
          boxShadow: const [
            BoxShadow(color: kInk, offset: Offset(1, 1), blurRadius: 0),
          ],
        ),
        child: Text(label, style: kSilkscreen(9, color: kInk, letterSpacing: 0.4)),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
    required this.icon,
    this.hint,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget icon;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? kInk : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: active
              ? const [
                  BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(
              label,
              style: kSilkscreen(10, color: kInk, letterSpacing: 0.5),
            ),
            if (hint != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: kButter,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: kInk, width: 1),
                ),
                child: Text(
                  hint!,
                  style: kSilkscreen(8, color: kInk, letterSpacing: 0.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String? _extOf(String url) {
  try {
    final segments = Uri.parse(url).pathSegments;
    if (segments.isEmpty) return null;
    final last = segments.last;
    final dot = last.lastIndexOf('.');
    if (dot < 0 || dot == last.length - 1) return null;
    return last.substring(dot + 1).toLowerCase();
  } catch (_) {
    return null;
  }
}

String? _sizeLabel(Map<String, dynamic>? artifact) {
  if (artifact == null) return null;
  final raw = artifact['size_bytes'] ?? artifact['size'] ?? artifact['bytes'];
  if (raw is num) return _formatBytes(raw.toInt());
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed != null) return _formatBytes(parsed);
  }
  return null;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}b';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} kb';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} mb';
}
