import 'package:flutter/material.dart';
import 'package:nova3d_frontend/core/theme.dart';
import 'package:nova3d_frontend/features/cad/models/texture_result.dart';
import 'package:nova3d_frontend/shared/services/texture_assets_downloader.dart';

/// The PBR tab: previews every asset a texture run returned (textured GLB,
/// PBR maps, per-tile albedo/relief deliverables, atlases, UV layouts, and
/// the settings manifest) and downloads them all as one folder-structured zip.
///
/// Assets are already resolved URLs (or inline text) carried on the message,
/// so this view needs no polling or provider — it renders directly and
/// packages on demand.
class PbrAssetsView extends StatefulWidget {
  const PbrAssetsView({super.key, required this.assets});

  final List<TextureAsset> assets;

  @override
  State<PbrAssetsView> createState() => _PbrAssetsViewState();
}

class _PbrAssetsViewState extends State<PbrAssetsView> {
  bool _downloading = false;

  Future<void> _downloadAll() async {
    if (_downloading || widget.assets.isEmpty) return;
    setState(() => _downloading = true);
    try {
      await downloadTextureAssetsZip(widget.assets);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not download the PBR assets.')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assets = widget.assets;
    if (assets.isEmpty) {
      return Container(
        color: kCream,
        alignment: Alignment.center,
        child: Text('No PBR assets.', style: kSilkscreen(10, color: kInkMuted)),
      );
    }

    return Container(
      color: kCream,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kLineSoft, width: 1.5)),
            ),
            child: Row(
              children: [
                Text(
                  '${assets.length} PBR ASSET${assets.length == 1 ? '' : 'S'}',
                  style: kSilkscreen(9, color: kInkSoft, letterSpacing: 0.5),
                ),
                const Spacer(),
                _DownloadAllButton(
                  downloading: _downloading,
                  onTap: _downloadAll,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final asset in assets) _AssetCard(asset: asset),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadAllButton extends StatelessWidget {
  const _DownloadAllButton({required this.downloading, required this.onTap});
  final bool downloading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: downloading ? null : onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: downloading ? kLineSoft : kLilac,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kInk, width: 1.5),
        boxShadow: const [
          BoxShadow(color: kInk, offset: Offset(1, 1), blurRadius: 0),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (downloading)
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
            )
          else
            const Icon(Icons.download_rounded, size: 13, color: kInk),
          const SizedBox(width: 6),
          Text(
            downloading ? 'PACKING…' : 'DOWNLOAD ALL',
            style: kSilkscreen(9, color: kInk, letterSpacing: 0.4),
          ),
        ],
      ),
    ),
  );
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset});
  final TextureAsset asset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kInk, width: 1.5),
              boxShadow: const [
                BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: asset.isImage
                ? Image.network(
                    asset.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _AssetIcon(),
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kLilac,
                              ),
                            ),
                          ),
                  )
                : const _AssetIcon(),
          ),
          const SizedBox(height: 6),
          Text(
            asset.displayLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kInk, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _AssetIcon extends StatelessWidget {
  const _AssetIcon();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(Icons.description_outlined, size: 28, color: kInkMuted),
  );
}
