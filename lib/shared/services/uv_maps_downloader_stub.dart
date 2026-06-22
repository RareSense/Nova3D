import 'package:nova3d_frontend/features/cad/models/uv_maps_result.dart';

/// Non-web fallback. The app ships on web; this only exists so the package
/// compiles for other targets.
Future<void> downloadUvMapsZip(
  UvMapsResult result, {
  String fileName = 'uv_maps.zip',
}) async {
  throw UnsupportedError('UV map download is only available on the web build.');
}
