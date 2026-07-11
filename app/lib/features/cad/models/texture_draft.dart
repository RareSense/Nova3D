import 'package:nova3d_frontend/features/cad/models/texture_request.dart';

/// A pending texture run whose source geometry is NOT a chat message but an
/// external model (a showcase entry). Stashed by conversation id and consumed
/// exactly once when the target [ChatPage] mounts — mirroring how a
/// [GenerationRequest] draft is handed off from the launcher to the chat page.
///
/// The geometry is carried as artifact maps (`{'url': ...}` or `{'uri': ...}`)
/// so the texture pipeline downloads it directly; the toolkit accepts either
/// shape. This never targets an AI-edited derivative — it is the exact model
/// the user chose to texture.
class TextureDraft {
  const TextureDraft({
    required this.request,
    required this.glbArtifact,
    required this.codeArtifact,
    required this.sourceId,
  });

  /// User-supplied texture inputs (prompt / reference image / resolution / key).
  final TextureRequest request;

  /// Source GLB as an artifact ref, e.g. `{'url': 'https://.../model.glb'}`.
  final Map<String, dynamic> glbArtifact;

  /// Source generation program as an artifact ref, e.g.
  /// `{'url': 'https://.../code.py'}`.
  final Map<String, dynamic> codeArtifact;

  /// Stable identity of the source model (e.g. `showcase-<entryId>`). Used as
  /// the per-source reentrancy key so one draft launches exactly one run.
  final String sourceId;
}
