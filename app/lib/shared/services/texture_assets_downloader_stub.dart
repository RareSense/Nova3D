import 'package:nova3d_frontend/features/cad/models/texture_result.dart';

/// Non-web fallback. The app ships on web; this only exists so the package
/// compiles for other targets.
Future<void> downloadTextureAssetsZip(
  List<TextureAsset> assets, {
  String fileName = 'pbr_textures.zip',
}) async {
  throw UnsupportedError('PBR asset download is only available on the web build.');
}
