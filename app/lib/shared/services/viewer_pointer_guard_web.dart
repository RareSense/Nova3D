import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Sets `pointer-events` on every viewer iframe on the page: `none` while a
/// modal is open (so Flutter widgets painted above the iframe receive taps),
/// `auto` to restore normal viewer interaction afterwards.
void setViewerIframesInteractive(bool interactive) {
  final value = interactive ? 'auto' : 'none';
  final iframes = web.document.getElementsByTagName('iframe');
  for (var i = 0; i < iframes.length; i++) {
    final element = iframes.item(i);
    if (element != null && element.isA<web.HTMLElement>()) {
      (element as web.HTMLElement).style.setProperty('pointer-events', value);
    }
  }
}
