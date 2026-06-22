import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Shows a GLB in a `<model-viewer>` element through a platform view. One
/// factory is registered per distinct src and reused across rebuilds.
class WebModelViewer extends StatelessWidget {
  const WebModelViewer({super.key, required this.src});

  final String src;

  static final Map<String, String> _viewTypeBySrc = {};
  static int _counter = 0;

  String _viewType() {
    return _viewTypeBySrc.putIfAbsent(src, () {
      final viewType = 'uv-checker-mv-${_counter++}';
      final url = src;
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        final el = web.document.createElement('model-viewer');
        el.setAttribute('src', url);
        el.setAttribute('camera-controls', '');
        el.setAttribute('auto-rotate', '');
        el.setAttribute('rotation-per-second', '18deg');
        el.setAttribute('interaction-prompt', 'none');
        el.setAttribute('exposure', '1.05');
        el.setAttribute('shadow-intensity', '0.5');
        el.setAttribute('loading', 'eager');
        el.setAttribute(
          'style',
          'width:100%;height:100%;background:#0f0f16;--poster-color:transparent;',
        );
        return el;
      });
      return viewType;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType());
  }
}
