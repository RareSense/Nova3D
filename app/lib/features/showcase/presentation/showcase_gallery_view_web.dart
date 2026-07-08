import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Renders the showcase gallery HTML in an iframe. The manifest URL is passed as
/// a query param; the gallery fetches that public JSON and renders the live-3D
/// grid. One factory is registered per manifest URL and reused across rebuilds.
class ShowcaseGalleryView extends StatelessWidget {
  const ShowcaseGalleryView({super.key, required this.manifestUrl});

  final String manifestUrl;

  static final Map<String, String> _viewTypeByUrl = {};
  static int _counter = 0;

  String _viewType() {
    return _viewTypeByUrl.putIfAbsent(manifestUrl, () {
      final viewType = 'nova3d-showcase-${_counter++}';
      final src =
          'showcase_gallery.html?manifest=${Uri.encodeQueryComponent(manifestUrl)}';
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        return web.HTMLIFrameElement()
          ..src = src
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none'
          ..setAttribute('title', 'Nova3D Showcase');
      });
      return viewType;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType());
}
