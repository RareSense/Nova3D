import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:nova3d_frontend/features/cad/models/texture_result.dart';
import 'package:web/web.dart' as web;

// Concurrent artifact fetches while zipping. Bounded so a large tile set
// cannot open dozens of parallel connections (browser queues + Azure rate
// limits), but downloads still overlap instead of running serially.
const _maxConcurrentFetches = 4;

/// Fetches every asset (signed Azure URLs need no auth — the same CORS
/// allowance that lets the app fetch GLB bytes covers these), embeds inline
/// assets (settings.json) directly, and packs everything into one zip
/// mirroring the asset folders. The download uses a base64 `data:` URL +
/// hidden anchor, matching the code/UV download mechanism.
Future<void> downloadTextureAssetsZip(
  List<TextureAsset> assets, {
  String fileName = 'pbr_textures.zip',
}) async {
  final dio = Dio();
  final archive = Archive();

  // Inline assets need no network; add them first so even a fully-offline
  // failure still yields the settings manifest alongside the error.
  final remote = <TextureAsset>[];
  for (final asset in assets) {
    final content = asset.content;
    if (content != null) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(asset.zipPath, bytes.length, bytes));
    } else if (asset.url.isNotEmpty) {
      remote.add(asset);
    }
  }

  for (var i = 0; i < remote.length; i += _maxConcurrentFetches) {
    final chunk = remote.skip(i).take(_maxConcurrentFetches).toList();
    final results = await Future.wait(
      chunk.map((asset) => _fetchBytes(dio, asset.url)),
    );
    for (var j = 0; j < chunk.length; j++) {
      final bytes = results[j];
      if (bytes == null) continue;
      archive.addFile(ArchiveFile(chunk[j].zipPath, bytes.length, bytes));
    }
  }

  if (archive.files.isEmpty) {
    throw StateError('No asset files could be downloaded.');
  }

  final zipped = ZipEncoder().encode(archive);
  if (zipped == null) throw StateError('Could not package the assets.');
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
