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
