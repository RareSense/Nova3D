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

const String kSketchTo3dWorkflow = 'sketch_to_3d';
const String kRegenerate3dPartWorkflow = 'regenerate_3d_part';
const String kAdd3dPartWorkflow = 'add_3d_part';
const String kArticulate3dModelWorkflow = 'articulate_3d_model';
const int kMaxReferenceImageBytes = 8 * 1024 * 1024;

// ── Storage keys ──────────────────────────────────────────────────────────────

const String kTokenKey = 'auth_token';
const String kUserKey = 'auth_user';
