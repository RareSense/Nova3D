import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/uv_maps_result.dart';
import 'package:nova3d_frontend/features/cad/state/uv_maps_provider.dart';
import 'package:nova3d_frontend/shared/services/uv_maps_downloader.dart';
import 'package:nova3d_frontend/shared/widgets/web_image.dart';

/// The "UV" tab body. Generates game-ready UV atlases for the CURRENT version's
/// code (never a new asset version), shows the flat sheets, and offers a single
/// structured-zip download (checker GLB + atlas SVGs).
class UvMapsView extends ConsumerStatefulWidget {
  const UvMapsView({
    super.key,
    required this.codeArtifact,
    this.sourceWorkflowId,
    this.conversationId,
    this.atlasMode = 'budget',
  });

  final Map<String, dynamic>? codeArtifact;
  final String? sourceWorkflowId;
  final String? conversationId;
  final String atlasMode;

  @override
  ConsumerState<UvMapsView> createState() => _UvMapsViewState();
}

class _UvMapsViewState extends ConsumerState<UvMapsView> {
  bool _downloading = false;

  String get _key =>
      uvMapsKey(widget.codeArtifact, sourceWorkflowId: widget.sourceWorkflowId);

  bool get _hasCode {
    final a = widget.codeArtifact;
    if (a == null) return false;
    final uri = a['uri'];
    final url = a['url'];
    return (uri is String && uri.isNotEmpty) || (url is String && url.isNotEmpty);
  }

  void _generate() {
    final code = widget.codeArtifact;
    if (code == null) return;
    ref.read(uvMapsProvider.notifier).generate(
          key: _key,
          codeArtifact: code,
          atlasMode: widget.atlasMode,
          conversationId: widget.conversationId,
        );
  }

  Future<void> _download(UvMapsResult result) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await downloadUvMapsZip(result, fileName: 'nova3d_uv_maps.zip');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('UV map download failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCode) {
      return const _UvMessage(
        icon: Icons.code_off,
        text:
            'This model has no editable source code yet. Generate it again to enable UV maps.',
      );
    }

    final st = ref.watch(uvMapsProvider)[_key] ?? UvMapsState.idle;
    return switch (st.phase) {
      UvPhase.idle => _UvIdle(onGenerate: _generate),
      UvPhase.running => _UvRunning(label: st.progress ?? 'Generating UV maps…'),
      UvPhase.failed => _UvFailed(
        error: st.error ?? 'UV maps could not be generated.',
        onRetry: () {
          ref.read(uvMapsProvider.notifier).reset(_key);
          _generate();
        },
      ),
      UvPhase.done => _UvDone(
        result: st.result!,
        downloading: _downloading,
        onDownload: () => _download(st.result!),
      ),
    };
  }
}

// ── Idle ──────────────────────────────────────────────────────────────────────
class _UvIdle extends StatelessWidget {
  const _UvIdle({required this.onGenerate});
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_on, size: 34, color: kLilac),
            const SizedBox(height: 12),
            Text(
              'Generate game-ready UV maps',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: kInk),
            ),
            const SizedBox(height: 6),
            const Text(
              'Unwraps this version into texture atlases. Packaged as a downloadable zip with the UV-mapped GLB.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kInkMuted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 16),
            _PrimaryButton(label: 'GENERATE UV MAPS', icon: Icons.auto_awesome, onTap: onGenerate),
          ],
        ),
      ),
    );
  }
}

// ── Running ───────────────────────────────────────────────────────────────────
class _UvRunning extends StatelessWidget {
  const _UvRunning({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: kLilac),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kInkMuted, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Failed ────────────────────────────────────────────────────────────────────
class _UvFailed extends StatelessWidget {
  const _UvFailed({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 30, color: kPink),
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kInkMuted, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 14),
            _PrimaryButton(label: 'TRY AGAIN', icon: Icons.refresh, onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

// ── Done ──────────────────────────────────────────────────────────────────────
class _UvDone extends StatelessWidget {
  const _UvDone({
    required this.result,
    required this.downloading,
    required this.onDownload,
  });
  final UvMapsResult result;
  final bool downloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      '${result.atlasCount} ${result.atlasCount == 1 ? 'sheet' : 'sheets'}',
      if (result.meshCount != null) '${result.meshCount} meshes',
      if (result.trisExportedTotal != null)
        '${_compact(result.trisExportedTotal!)} tris',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meta,
                  style: kSilkscreen(9, color: kInkMuted, letterSpacing: 0.4),
                ),
              ),
              _PrimaryButton(
                label: downloading ? 'PREPARING…' : 'DOWNLOAD MAPS',
                icon: Icons.download,
                busy: downloading,
                onTap: downloading ? null : onDownload,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final atlas in result.atlases)
                    _AtlasThumb(atlas: atlas),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

class _AtlasThumb extends StatelessWidget {
  const _AtlasThumb({required this.atlas});
  final UvMapAtlas atlas;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kInk, width: 1.5),
            boxShadow: const [
              BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: WebImage(src: atlas.svgUrl),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 132,
          child: Text(
            atlas.group,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: kSilkscreen(8, color: kInkMuted, letterSpacing: 0.3),
          ),
        ),
      ],
    );
  }
}

// ── Shared bits ───────────────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: onTap == null ? kSurface : kLilacBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kInk, width: 1.5),
          boxShadow: const [
            BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
              )
            else
              Icon(icon, size: 14, color: kInk),
            const SizedBox(width: 7),
            Text(label, style: kSilkscreen(10, color: kInk, letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }
}

class _UvMessage extends StatelessWidget {
  const _UvMessage({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: kInkMuted),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kInkMuted, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
