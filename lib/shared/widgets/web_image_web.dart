import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Displays an image URL through an HTML `<img>` platform view. Works for SVG
/// (the browser renders it natively). One platform-view factory is registered
/// per distinct src and reused, so rebuilds don't leak factories.
class WebImage extends StatelessWidget {
  const WebImage({super.key, required this.src});

  final String src;

  static final Map<String, String> _viewTypeBySrc = {};
  static int _counter = 0;

  String _viewType() {
    return _viewTypeBySrc.putIfAbsent(src, () {
      final viewType = 'uv-atlas-img-${_counter++}';
      final url = src;
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        final img = web.HTMLImageElement()
          ..src = url
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'contain'
          ..style.background = '#0f0f16'
          ..setAttribute('decoding', 'async')
          ..setAttribute('loading', 'lazy');
        return img;
      });
      return viewType;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType());
  }
}
