import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('nova3dModelCache.store')
external JSPromise<JSString?> _storeModel(JSString src);

@JS('nova3dModelCache.revoke')
external void _revokeObjectUrl(JSString src);

class GlbAssetCache {
  const GlbAssetCache._();

  /// Returns a blob URL for [src], or null if the URL is inaccessible
  /// (e.g. expired SAS token). Callers should handle null by refreshing the URL.
  static Future<String?> resolve(String src) async {
    if (!kIsWeb || src.startsWith('assets/')) return src;

    try {
      final resolved = await _storeModel(src.toJS).toDart;
      return resolved?.toDart; // null when store() returned null (HTTP error)
    } catch (_) {
      return null;
    }
  }

  static void revoke(String src) {
    if (!kIsWeb || !src.startsWith('blob:')) return;

    try {
      _revokeObjectUrl(src.toJS);
    } catch (_) {}
  }
}
