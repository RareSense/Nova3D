/// Packages a texture run's PBR assets (maps + atlases + material spec) into a
/// single downloadable zip, grouped into `maps/` and `atlases/` folders. Web
/// builds fetch the signed artifact bytes and trigger a browser download;
/// non-web compilation falls back to a stub.
library;

export 'texture_assets_downloader_stub.dart'
    if (dart.library.js_interop) 'texture_assets_downloader_web.dart';
