/// Packages a texture run's assets (textured GLB, PBR maps, per-tile
/// deliverables, atlases, UV layouts, settings manifest) into a single
/// downloadable zip mirroring the asset folders. Web builds fetch the signed
/// artifact bytes and trigger a browser download; non-web compilation falls
/// back to a stub.
library;

export 'texture_assets_downloader_stub.dart'
    if (dart.library.js_interop) 'texture_assets_downloader_web.dart';
