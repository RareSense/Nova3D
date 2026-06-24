/// Renders an image URL (including SVG, which `Image.network` cannot decode
/// under CanvasKit) via a lightweight HTML `<img>` platform view on web.
library;

export 'web_image_stub.dart' if (dart.library.js_interop) 'web_image_web.dart';
