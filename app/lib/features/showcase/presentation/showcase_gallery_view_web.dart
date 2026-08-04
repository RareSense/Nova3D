import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Renders the showcase gallery HTML in an iframe. The manifest URL is passed as
/// a query param; the gallery fetches that public JSON and renders the live-3D
/// grid. One factory is registered per manifest URL and reused across rebuilds.
///
/// [tab] selects which catalog tab (generations | textures | rings) is shown.
/// It seeds the iframe's initial `&tab=` on first load; later tab changes driven
/// by the app URL are pushed into the already-mounted iframe via [setTab] rather
/// than recreating it (which would reload the whole Three.js gallery).
class ShowcaseGalleryView extends StatelessWidget {
  const ShowcaseGalleryView({super.key, required this.manifestUrl, this.tab});

  final String manifestUrl;
  final String? tab;

  static final Map<String, String> _viewTypeByUrl = {};
  static final Map<String, web.HTMLIFrameElement> _iframeByUrl = {};
  static int _counter = 0;

  /// Tell the mounted gallery iframe to switch tabs (app URL → gallery). No-op
  /// if the iframe for [manifestUrl] has not been created yet.
  static void setTab(String manifestUrl, String tab) {
    _iframeByUrl[manifestUrl]?.contentWindow?.postMessage(
      {'type': 'nova3d-showcase-set-tab', 'tab': tab}.jsify(),
      web.window.location.origin.toJS,
    );
  }

  /// Whether [source] is the window of this manifest's mounted gallery iframe.
  static bool isMessageSource(String manifestUrl, Object? source) =>
      source != null && source == _iframeByUrl[manifestUrl]?.contentWindow;

  String _viewType() {
    return _viewTypeByUrl.putIfAbsent(manifestUrl, () {
      final viewType = 'nova3d-showcase-${_counter++}';
      final initialTab = (tab != null && tab!.isNotEmpty) ? '&tab=$tab' : '';
      final src =
          'showcase_gallery.html?manifest=${Uri.encodeQueryComponent(manifestUrl)}$initialTab';
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        final frame = web.HTMLIFrameElement()
          ..src = src
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none'
          ..setAttribute('title', 'Nova3D Showcase');
        _iframeByUrl[manifestUrl] = frame;
        return frame;
      });
      return viewType;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType());
}
