import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:nova3d_frontend/features/cad/models/uv_maps_result.dart';
import 'package:web/web.dart' as web;

/// Fetches the checker GLB + every atlas SVG from their signed URLs, packs them
/// into one structured zip, and triggers a browser download. Signed Azure URLs
/// need no auth; the app already fetches GLB bytes cross-origin, so the same
/// CORS allowance covers these requests. The download itself uses a base64
/// `data:` URL + hidden anchor — the same mechanism the code download uses.
Future<void> downloadUvMapsZip(
  List<UvMapsSet> sets, {
  String fileName = 'uv_maps.zip',
}) async {
  final dio = Dio();
  final archive = Archive();

  for (final set in sets) {
    final result = set.result;
    final folder = set.slug;

    final checkerUrl = result.checkerGlbUrl;
    if (checkerUrl != null && checkerUrl.isNotEmpty) {
      final bytes = await _fetchBytes(dio, checkerUrl);
      if (bytes != null) {
        archive.addFile(
          ArchiveFile('$folder/model_checker.glb', bytes.length, bytes),
        );
      }
    }
    for (final atlas in result.atlases) {
      final bytes = await _fetchBytes(dio, atlas.svgUrl);
      if (bytes == null) continue;
      archive.addFile(
        ArchiveFile('$folder/${atlas.zipPath()}', bytes.length, bytes),
      );
    }
  }

  if (archive.files.isEmpty) {
    throw StateError('No UV map files could be downloaded.');
  }

  final zipped = ZipEncoder().encode(archive);
  if (zipped == null) throw StateError('Could not package the UV maps.');
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
