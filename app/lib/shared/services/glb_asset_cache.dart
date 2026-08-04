import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('nova3dModelCache.store')
external JSPromise<JSString?> _storeModel(JSString src);

@JS('nova3dModelCache.revoke')
external void _revokeObjectUrl(JSString src);

@JS('nova3dModelCache.clearPrivateData')
external JSPromise<JSBoolean> _clearPrivateData();

class GlbAssetCache {
  const GlbAssetCache._();

  static const Duration _resolveTimeout = Duration(seconds: 45);
  static const Duration _clearTimeout = Duration(seconds: 8);

  /// Returns a blob URL for [src], or null if the URL is inaccessible
  /// (e.g. expired SAS token). Callers should handle null by refreshing the URL.
  static Future<String?> resolve(String src) async {
    if (!kIsWeb || src.startsWith('assets/')) return src;

    try {
      final resolved = await _storeModel(
        src.toJS,
      ).toDart.timeout(_resolveTimeout);
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

  /// Clears model/editor data that must never cross an authentication boundary.
  /// The browser implementation has its own deadlines; this outer timeout also
  /// protects auth transitions if the JS bridge itself is unavailable or stuck.
  static Future<bool> clearPrivateData() async {
    if (!kIsWeb) return true;

    try {
      final result = await _clearPrivateData().toDart.timeout(_clearTimeout);
      return result.toDart;
    } catch (_) {
      return false;
    }
  }
}
