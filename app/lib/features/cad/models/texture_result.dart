/// One downloadable PBR asset returned by `texture_3d_v2` (a map, atlas, or the
/// material spec). [folder] groups it inside the download zip; [name] is the
/// file name within that folder.
class TextureAsset {
  const TextureAsset({
    required this.folder,
    required this.name,
    required this.url,
    this.label,
  });

  final String folder; // '' | 'maps' | 'atlases'
  final String name; // e.g. 'albedo.png'
  final String url; // signed download URL
  final String? label; // human label for the UI (falls back to [name])

  String get zipPath => folder.isEmpty ? name : '$folder/$name';
  String get displayLabel => label ?? name;
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
    if (label != null) 'label': label,
  };

  factory TextureAsset.fromJson(Map<String, dynamic> j) => TextureAsset(
    folder: (j['folder'] as String?) ?? '',
    name: (j['name'] as String?) ?? 'asset',
    url: (j['url'] as String?) ?? '',
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

  /// Collects the PBR maps, atlases, and material spec from the success payload
  /// into a flat, folder-grouped asset list (download order).
  static List<TextureAsset> _extractAssets(Map<String, dynamic> success) {
    final assets = <TextureAsset>[];

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
      final url = _artifactUrl(maps[name]);
      if (url == null) continue;
      assets.add(
        TextureAsset(
          folder: 'maps',
          name: '$name.png',
          url: url,
          label: '${name[0].toUpperCase()}${name.substring(1)} map',
        ),
      );
    }

    // Atlases (painted colour + relief), if present.
    void addAtlas(String key, String file, String label) {
      final url = _artifactUrl(success[key]);
      if (url != null) {
        assets.add(
          TextureAsset(folder: 'atlases', name: file, url: url, label: label),
        );
      }
    }

    addAtlas('painted_atlas_artifact', 'painted_atlas.png', 'Painted atlas');
    addAtlas('relief_atlas_artifact', 'relief_atlas.png', 'Relief atlas');

    // Material spec (glTF material definitions).
    final materialsUrl = _artifactUrl(success['materials_artifact']);
    if (materialsUrl != null) {
      assets.add(
        TextureAsset(
          folder: '',
          name: 'materials.json',
          url: materialsUrl,
          label: 'Material spec',
        ),
      );
    }

    return assets;
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
