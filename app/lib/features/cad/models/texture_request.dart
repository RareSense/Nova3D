/// User-supplied inputs for one `texture_3d_v2` run, collected by the Magic
/// Texture dialog. The source geometry (`glb_artifact` + `code_artifact`) is NOT
/// part of this object — it comes from the original generation message the
/// request was launched from, so texturing always targets that specific model
/// and never an AI-edited / articulated derivative.
library;

/// Texture resolution presets exposed in the UI.
///
/// The GraphFlow `texture_3d_v2` spec maps a single UI resolution onto three
/// separate root fields (see its header comment): the integer atlas/PBR sizes
/// and the string `paint_image_size` token. Keeping the mapping here — the one
/// place that knows the UI selection — avoids scattering magic numbers.
enum TextureResolution {
  k1('1K', 1024),
  k2('2K', 2048),
  k4('4K', 4096);

  const TextureResolution(this.token, this.pixels);

  /// `paint_image_size` value — must be one of the toolkit's IMAGE_SIZES.
  final String token;

  /// `texture_atlas_size` and `pbr_texture_size` value, in pixels.
  final int pixels;

  String get label => token;

  /// The default flash image model is capped at 1K by its route (the server
  /// clamps larger requests). TRUE 2K/4K painting requires the explicit
  /// pro-image tier — without it the selector only upscales 1K paint into a
  /// larger atlas. Costs more per image call; the dialog says so.
  bool get needsProImageTier => this != TextureResolution.k1;
}

/// Explicit tier for native ≥2K paint calls (see the toolkit's
/// `nova3d_texture_paint` profile).
const String kProImagePaintTier = 'gemini_3_pro_image_google';

class TextureRequest {
  const TextureRequest({
    required this.prompt,
    required this.referenceImageDataUrl,
    required this.resolution,
    required this.geminiApiKey,
  });

  /// Optional natural-language material intent → `texture_description`.
  final String prompt;

  /// Optional single reference photo as a `data:` URL → `reference_image_artifact`.
  final String? referenceImageDataUrl;

  final TextureResolution resolution;

  /// Gemini (Google) key used at every provider call in the pipeline.
  final String geminiApiKey;

  bool get hasPrompt => prompt.trim().isNotEmpty;

  bool get hasReferenceImage => (referenceImageDataUrl ?? '').trim().isNotEmpty;

  /// Root payload fields for `POST /run/state/texture_3d_v2`. Only fields the
  /// user actually provided are included; everything else falls back to the
  /// workflow's lab defaults server-side.
  Map<String, dynamic> toPayload({
    required Map<String, dynamic> glbArtifact,
    required Map<String, dynamic> codeArtifact,
  }) => {
    'glb_artifact': glbArtifact,
    'code_artifact': codeArtifact,
    'gemini_api_key': geminiApiKey.trim(),
    'texture_atlas_size': resolution.pixels,
    'paint_image_size': resolution.token,
    'pbr_texture_size': resolution.pixels,
    if (resolution.needsProImageTier) 'paint_image_tier': kProImagePaintTier,
    if (hasPrompt) 'texture_description': prompt.trim(),
    if (hasReferenceImage)
      'reference_image_artifact': referenceImageDataUrl!.trim(),
  };
}
