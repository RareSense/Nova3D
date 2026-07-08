/// Embeds the standalone Three.js showcase gallery (`web/showcase_gallery.html`)
/// as an iframe. The gallery is read-only — it only fetches the public manifest
/// URL passed to it and never writes anything. Non-web compilation is a stub.
library;

export 'showcase_gallery_view_stub.dart'
    if (dart.library.js_interop) 'showcase_gallery_view_web.dart';
