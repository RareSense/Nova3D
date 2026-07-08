import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:nova3d_frontend/features/cad/models/texture_result.dart';
import 'package:web/web.dart' as web;

/// Fetches every PBR asset from its signed URL and packs them into one zip with
/// `maps/` and `atlases/` subfolders, then triggers a browser download. Signed
/// Azure URLs need no auth — the same CORS allowance that lets the app fetch GLB
/// bytes covers these. The download uses a base64 `data:` URL + hidden anchor,
/// matching the code/UV download mechanism.
Future<void> downloadTextureAssetsZip(
  List<TextureAsset> assets, {
  String fileName = 'pbr_textures.zip',
}) async {
  final dio = Dio();
  final archive = Archive();

  for (final asset in assets) {
    if (asset.url.isEmpty) continue;
    final bytes = await _fetchBytes(dio, asset.url);
    if (bytes == null) continue;
    archive.addFile(ArchiveFile(asset.zipPath, bytes.length, bytes));
  }

  if (archive.files.isEmpty) {
    throw StateError('No PBR asset files could be downloaded.');
  }

  final zipped = ZipEncoder().encode(archive);
  if (zipped == null) throw StateError('Could not package the PBR assets.');
  _save(fileName, zipped);
}

Future<List<int>?> _fetchBytes(Dio dio, String url) async {
  try {
    final resp = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return resp.data;
  } catch (_) {
    return null;
  }
}

void _save(String fileName, List<int> bytes) {
  final href = 'data:application/zip;base64,${base64Encode(bytes)}';
  final anchor = web.HTMLAnchorElement()
    ..href = href
    ..download = fileName
    ..rel = 'noopener'
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
