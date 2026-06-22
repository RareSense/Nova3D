/// Parsed result of the `generate_uv_maps` workflow (the `uv_unwrap` node).
///
/// The `generate_uv_maps` workflow returns `return_nodes: ['uv_unwrap']`, so the
/// `/result/{id}` body is `{ "uv_unwrap": [ <tool result map> ] }`. The tool
/// result carries the checker GLB, the per-group atlas sheets, and diagnostics.
/// This model never becomes an asset version — UV maps are a derived download
/// attached to whichever version's `code_artifact` produced them.
class UvMapAtlas {
  const UvMapAtlas({
    required this.group,
    required this.subfolder,
    required this.svgUrl,
    this.svgUri,
  });

  final String group;
  final String subfolder; // e.g. "atlases/Body"
  final String svgUrl; // signed download URL
  final String? svgUri;

  /// File name used inside the downloaded zip, e.g. "atlases/Body/atlas_Body.svg".
  String zipPath() {
    final name = _fileNameFromUrl(svgUrl) ?? 'atlas_$group.svg';
    final folder = subfolder.isEmpty ? 'atlases' : subfolder;
    return '$folder/$name';
  }
}

/// One labelled packing in a UV bundle (e.g. "Combined" or "Per-group").
class UvMapsSet {
  const UvMapsSet({required this.label, required this.result});

  final String label;
  final UvMapsResult result;

  /// Filesystem-safe folder name for this set inside the download zip.
  String get slug {
    final s = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return s.replaceAll(RegExp(r'^_+|_+$'), '').isEmpty ? 'set' : s;
  }

  Map<String, dynamic> toJson() => {'label': label, 'result': result.toJson()};

  factory UvMapsSet.fromJson(Map<String, dynamic> j) => UvMapsSet(
    label: (j['label'] as String?) ?? 'Set',
    result: UvMapsResult.fromJson(
      (j['result'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );
}

class UvMapsResult {
  const UvMapsResult({
    required this.ok,
    required this.status,
    this.checkerGlbUrl,
    this.atlases = const [],
    this.atlasCount = 0,
    this.meshCount,
    this.trisExportedTotal,
    this.failed = false,
    this.errorMessage,
  });

  final bool ok;
  final String status;
  final String? checkerGlbUrl;
  final List<UvMapAtlas> atlases;
  final int atlasCount;
  final int? meshCount;
  final int? trisExportedTotal;
  final bool failed;
  final String? errorMessage;

  bool get hasMaps =>
      !failed && (checkerGlbUrl != null || atlases.isNotEmpty);

  // ── Local persistence (so generated maps survive a page refresh) ──────────
  // Azure SAS URLs are long-lived (AZURE_SAS_MINUTES), so the URLs are stored
  // directly. Only successful results are ever persisted.
  Map<String, dynamic> toJson() => {
    'status': status,
    'checker': checkerGlbUrl,
    'atlasCount': atlasCount,
    'meshCount': meshCount,
    'tris': trisExportedTotal,
    'atlases': atlases
        .map((a) => {
              'group': a.group,
              'subfolder': a.subfolder,
              'svgUrl': a.svgUrl,
              'svgUri': a.svgUri,
            })
        .toList(),
  };

  factory UvMapsResult.fromJson(Map<String, dynamic> j) => UvMapsResult(
    ok: true,
    status: (j['status'] as String?) ?? 'completed',
    checkerGlbUrl: j['checker'] as String?,
    atlasCount: (j['atlasCount'] as num?)?.toInt() ?? 0,
    meshCount: (j['meshCount'] as num?)?.toInt(),
    trisExportedTotal: (j['tris'] as num?)?.toInt(),
    atlases: (j['atlases'] as List?)
            ?.whereType<Map>()
            .map((e) => UvMapAtlas(
                  group: (e['group'] as String?) ?? 'group',
                  subfolder: (e['subfolder'] as String?) ?? 'atlases',
                  svgUrl: (e['svgUrl'] as String?) ?? '',
                  svgUri: e['svgUri'] as String?,
                ))
            .where((a) => a.svgUrl.isNotEmpty)
            .toList() ??
        const [],
  );

  /// Parse the `/result/{id}` body for a `generate_uv_maps` run.
  factory UvMapsResult.fromResultJson(Map<String, dynamic> json) {
    final payload = _nodePayload(json) ?? json;
    final r = _unwrapResult(payload);

    final status = (r['status'] as String?) ?? '';
    final ok = r['ok'] == true;
    final failed = !ok || status == 'failed';

    final atlases = <UvMapAtlas>[];
    final rawAtlases = r['atlas_artifacts'];
    if (rawAtlases is List) {
      for (final entry in rawAtlases) {
        if (entry is! Map) continue;
        final e = _asStringMap(entry)!;
        final svg = _asStringMap(e['svg_artifact']);
        final url = svg?['url'] as String?;
        if (url == null || url.isEmpty) continue;
        atlases.add(
          UvMapAtlas(
            group: (e['group'] as String?) ?? 'group',
            subfolder: (e['subfolder'] as String?) ?? 'atlases',
            svgUrl: url,
            svgUri: svg?['uri'] as String?,
          ),
        );
      }
    }

    final diagnostics = _asStringMap(r['diagnostics']) ?? const {};

    return UvMapsResult(
      ok: ok,
      status: status,
      checkerGlbUrl: _artifactUrl(r['checker_glb_artifact']),
      atlases: atlases,
      atlasCount: _intOf(diagnostics['atlas_count']) ?? atlases.length,
      meshCount: _intOf(diagnostics['mesh_count']),
      trisExportedTotal: _intOf(diagnostics['tris_exported_total']),
      failed: failed,
      errorMessage: failed
          ? ((r['user_message'] as String?) ??
                (_asStringMap(r['failure'])?['user_message'] as String?) ??
                'UV map generation did not produce maps.')
          : null,
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static Map<String, dynamic>? _nodePayload(Map<String, dynamic> json) {
    final node = json['uv_unwrap'];
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

  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

String? _fileNameFromUrl(String url) {
  try {
    final segments = Uri.parse(url).pathSegments;
    if (segments.isEmpty) return null;
    final last = segments.last.trim();
    return last.isEmpty ? null : last;
  } catch (_) {
    return null;
  }
}
