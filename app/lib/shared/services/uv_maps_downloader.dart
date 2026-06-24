/// Client-side packaging of a UvMapsResult into a single downloadable zip
/// (checker GLB + the per-group atlas SVGs in `atlases/<group>/`). Web builds
/// fetch the signed artifact bytes and trigger a browser download; non-web
/// compilation falls back to a stub.
library;

export 'uv_maps_downloader_stub.dart'
    if (dart.library.js_interop) 'uv_maps_downloader_web.dart';
