/// Renders a GLB URL in a `<model-viewer>` web component (registered in
/// web/index.html) via a platform view on web; a stub elsewhere.
library;

export 'web_model_viewer_stub.dart'
    if (dart.library.js_interop) 'web_model_viewer_web.dart';
