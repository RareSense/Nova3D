import 'dart:convert';

/// One downloadable asset from a `texture_3d_v2` run: the textured GLB, a PBR
/// map, a per-tile deliverable, an atlas, a UV layout, or the inline
/// settings manifest. [folder] groups it inside the download zip; [name] is
/// the file name within that folder. Exactly one of [url] (remote fetch) or
/// [content] (inline text, e.g. settings.json) is non-empty.
class TextureAsset {
  const TextureAsset({
    required this.folder,
    required this.name,
    this.url = '',
    this.content,
    this.label,
  });

  final String folder; // '' | 'maps' | 'tiles/albedo' | 'tiles/relief' | 'atlases' | 'uv'
  final String name; // e.g. 'albedo.png'
  final String url; // signed download URL ('' for inline assets)
  final String? content; // inline text body (settings.json)
  final String? label; // human label for the UI (falls back to [name])

  String get zipPath => folder.isEmpty ? name : '$folder/$name';
  String get displayLabel => label ?? name;
  bool get isInline => content != null;
  bool get isImage {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  Map<String, dynamic> toJson() => {
    'folder': folder,
    'name': name,
    'url': url,
    if (content != null) 'content': content,
    if (label != null) 'label': label,
  };

  factory TextureAsset.fromJson(Map<String, dynamic> j) => TextureAsset(
    folder: (j['folder'] as String?) ?? '',
    name: (j['name'] as String?) ?? 'asset',
    url: (j['url'] as String?) ?? '',
    content: j['content'] as String?,
    label: j['label'] as String?,
  );
}

/// Parsed result of the `texture_3d_v2` workflow.
///
/// The client requests `return_nodes: ['final_textured', 'fail_texture_*]`, so
/// the `/result/{id}` body is `{ "final_textured": [ <map> ], ... }` on success,
/// or carries one of the `fail_texture_*` node payloads on failure. The success
/// payload exposes the textured GLB (`glb_artifact`), the derived PBR maps
/// (`map_artifacts`), the painted/relief atlases, and the material spec.
///
/// Texturing bakes maps onto existing geometry — it does NOT emit a new program
/// — so this result has no `code_artifact`. Callers reuse the source
/// generation's code artifact for the CODE / UV tabs.
class TextureResult {
  const TextureResult({
    this.glbUrl,
    this.modelArtifact,
    this.assets = const [],
    this.failed = false,
    this.errorMessage,
  });

  final String? glbUrl;
  final Map<String, dynamic>? modelArtifact;

  /// Downloadable PBR assets (maps + atlases + material spec), for the PBR tab.
  final List<TextureAsset> assets;
  final bool failed;
  final String? errorMessage;

  /// Parse the `/result/{id}` body for a `texture_3d_v2` run.
  factory TextureResult.fromResultJson(Map<String, dynamic> json) {
    final success = _successPayload(json);
    if (success != null) {
      final glbUrl = _artifactUrl(success['glb_artifact']) ??
          _artifactUrl(success['model_artifact']) ??
          (success['model_url'] as String?);
      final modelArtifact = _asStringMap(success['glb_artifact']) ??
          _asStringMap(success['model_artifact']);
      if (glbUrl != null && glbUrl.isNotEmpty) {
        return TextureResult(
          glbUrl: glbUrl,
          modelArtifact: modelArtifact,
          assets: _extractAssets(success),
        );
      }
    }

    // No usable GLB → failure. Prefer the most specific per-stage message the
    // workflow's fail nodes emitted; fall back to the root error, then generic.
    final failureMessage = _failureMessage(json) ?? _rootError(json);
    return TextureResult(
      failed: true,
      errorMessage:
          failureMessage ?? 'Texturing did not produce a textured model.',
    );
  }

  /// Collects everything a 3D artist can use from the success payload into a
  /// flat, folder-grouped asset list (download order):
  ///
  ///   model.glb            the textured model
  ///   maps/                the 6 derived PBR maps
  ///   tiles/albedo/        the generated image for each painted cell
  ///   tiles/relief/        the generated height tile for each painted cell
  ///   atlases/             assembled painted + relief atlases
  ///   uv/                  layout raster/labeled/SVG + full UV wireframe
  ///   settings.json        the exact pipeline settings the run used
  ///
  /// Internal pipeline artifacts (material spec, batch maps, prompts, masks)
  /// are deliberately NOT exposed — they are workflow internals, not assets.
  static List<TextureAsset> _extractAssets(Map<String, dynamic> success) {
    final assets = <TextureAsset>[];

    void addUrl(String folder, String name, Object? artifact, String label) {
      final url = _artifactUrl(artifact);
      if (url != null) {
        assets.add(
          TextureAsset(folder: folder, name: name, url: url, label: label),
        );
      }
    }

    addUrl('', 'model.glb', success['glb_artifact'], 'Textured model');

    // PBR maps: pbr_derive.map_artifacts → { albedo|height|normal|roughness|
    // metallic|ao : <artifact> }. Fixed order so the UI reads consistently.
    const mapOrder = [
      'albedo',
      'normal',
      'roughness',
      'metallic',
      'ao',
      'height',
    ];
    final maps = _asStringMap(success['map_artifacts']) ?? const {};
    final seen = <String>{};
    for (final name in [...mapOrder, ...maps.keys]) {
      if (name.isEmpty || !seen.add(name)) continue;
      addUrl(
        'maps',
        '$name.png',
        maps[name],
        '${name[0].toUpperCase()}${name.substring(1)} map',
      );
    }

    // Per-tile deliverables: one generated albedo (and relief, when the relief
    // pass ran) image per painted cell, keyed by cell id.
    void addTiles(String key, String folder, String labelPrefix) {
      final tiles = _asStringMap(success[key]) ?? const {};
      for (final cell in tiles.keys.toList()..sort()) {
        addUrl(folder, '${_fileSafe(cell)}.png', tiles[cell], '$labelPrefix · $cell');
      }
    }

    addTiles('tile_artifacts', 'tiles/albedo', 'Tile');
    addTiles('relief_tile_artifacts', 'tiles/relief', 'Relief');

    addUrl(
      'atlases',
      'painted_atlas.png',
      success['painted_atlas_artifact'],
      'Painted atlas',
    );
    addUrl(
      'atlases',
      'relief_atlas.png',
      success['relief_atlas_artifact'],
      'Relief atlas',
    );

    // UV layout: where each part lives on the atlas, plus the full wireframe
    // (island outlines + internal mesh edges) — the retexture/paint-over map.
    addUrl('uv', 'layout.png', success['layout_png_artifact'], 'UV layout');
    addUrl(
      'uv',
      'layout_labeled.png',
      success['layout_labeled_png_artifact'],
      'UV layout (labeled)',
    );
    addUrl(
      'uv',
      'layout.svg',
      success['layout_svg_artifact'],
      'UV layout (SVG)',
    );
    addUrl(
      'uv',
      'uv_wireframe.png',
      success['uv_wireframe_artifact'],
      'UV wireframe',
    );

    final settings = _settingsJson(success);
    if (settings != null) {
      assets.add(
        TextureAsset(
          folder: '',
          name: 'settings.json',
          content: settings,
          label: 'Pipeline settings',
        ),
      );
    }

    return assets;
  }

  /// The pipeline settings that shaped these assets, straight from the run's
  /// own diagnostics (seam bake repeat/margin, PBR derive sizes and modes,
  /// batch layout) — what an artist needs to reproduce or match the bake.
  static String? _settingsJson(Map<String, dynamic> success) {
    final settings = <String, dynamic>{
      if (success['seam_diagnostics'] is Map)
        'seam_bake': success['seam_diagnostics'],
      if (success['pbr_diagnostics'] is Map)
        'pbr_derive': success['pbr_diagnostics'],
      if (success['assemble_diagnostics'] is Map)
        'paint_batches': success['assemble_diagnostics'],
      if (success['batch_count'] != null)
        'paint_batch_count': success['batch_count'],
    };
    if (settings.isEmpty) return null;
    return const JsonEncoder.withIndent('  ').convert(settings);
  }

  static String _fileSafe(String name) {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return safe.isEmpty ? 'tile' : safe;
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// The `final_textured` node payload, if present and non-empty.
  static Map<String, dynamic>? _successPayload(Map<String, dynamic> json) {
    final payload = _nodePayload(json['final_textured']);
    if (payload == null) return null;
    return _unwrapResult(payload);
  }

  /// First `fail_texture_*` node payload that carries a human message.
  static String? _failureMessage(Map<String, dynamic> json) {
    const failNodes = [
      'fail_texture_plan',
      'fail_texture_paint',
      'fail_texture_bake',
      'fail_pbr_derive',
      'fail_texture_apply',
    ];
    for (final key in failNodes) {
      final payload = _nodePayload(json[key]);
      if (payload == null) continue;
      final r = _unwrapResult(payload);
      final message = (r['user_message'] as String?) ??
          (_asStringMap(r['failure'])?['user_message'] as String?) ??
          (_asStringMap(r['failure'])?['message'] as String?) ??
          (r['reason'] as String?);
      if (message != null && message.trim().isNotEmpty) return message.trim();
    }
    return null;
  }

  static Map<String, dynamic>? _nodePayload(Object? node) {
    if (node is List && node.isNotEmpty && node.first is Map) {
      return _asStringMap(node.first);
    }
    if (node is Map) return _asStringMap(node);
    return null;
  }

  static Map<String, dynamic> _unwrapResult(Map<String, dynamic> payload) {
    final inner = payload['result'];
    if (inner is Map) return _asStringMap(inner)!;
    return payload;
  }

  static String? _rootError(Map<String, dynamic> json) {
    final error = json['error'] ?? json['detail'] ?? json['message'];
    if (error is String && error.trim().isNotEmpty) return error.trim();
    if (error is Map) {
      final message = error['user_message'] ?? error['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
    }
    return null;
  }

  static String? _artifactUrl(Object? artifact) {
    if (artifact is Map) {
      final url = artifact['url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}
