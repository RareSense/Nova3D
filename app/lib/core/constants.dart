const String kAuthBaseUrl = String.fromEnvironment(
  'AUTH_BASE_URL',
  defaultValue: 'https://nova3d.xyz',
);

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://nova3d.xyz/api',
);

// ── Nova3D GraphFlow generation API ───────────────────────────────────────────

const String kCadBaseUrl = String.fromEnvironment(
  'CAD_BASE_URL',
  defaultValue: 'https://nova3d.xyz/api',
);

const String kSketchTo3dPaidWorkflow = 'sketch_to_3d_v2';
const String kSketchTo3dByokWorkflow = 'sketch_to_3d_byok_v2';
const String kRegenerate3dPartWorkflow = 'regenerate_3d_part';
const String kAdd3dPartWorkflow = 'add_3d_part';
const String kArticulate3dModelWorkflow = 'articulate_3d_model';
const String kGenerateUvMapsWorkflow = 'generate_uv_maps';
const String kTexture3dWorkflow = 'texture_3d_v2';

// Public showcase manifest (a static JSON on a public bucket). Read-only; the
// app never writes it. The default points at Nova3D's public showcase bucket so
// the hosted build works with no extra config. This is only a public read URL
// (the account name already appears in every anonymously-served blob URL) — it
// is NOT a credential; the account key lives solely in gitignored publish tools.
// Self-hosters can point elsewhere at build time, e.g.
// --dart-define=SHOWCASE_MANIFEST_URL=https://<acct>.blob.core.windows.net/showcase/showcase.json
const String kShowcaseManifestUrl = String.fromEnvironment(
  'SHOWCASE_MANIFEST_URL',
  defaultValue:
      'https://nova3dshowcase.blob.core.windows.net/showcase/showcase.json',
);
const int kMaxReferenceImageBytes = 8 * 1024 * 1024;
const int kMaxReferenceImageCount = 3;
const int kMaxReferenceImageDimension = 512;
const int kMaxGenerationPromptWords = 40;

// ── Storage keys ──────────────────────────────────────────────────────────────

const String kTokenKey = 'auth_token';
const String kUserKey = 'auth_user';

// ── Layout ────────────────────────────────────────────────────────────────────

const double kSidebarBreakpoint = 768;
const double kSidebarWidth = 260;
const double kInputCompactBreakpoint = 560;
const double kContentMaxWidth = 800;
const double kBubbleMaxWidth = 640;
const double kViewerDefaultHeight = 400;
