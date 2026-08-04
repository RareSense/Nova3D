const String kAuthBaseUrl = String.fromEnvironment(
  'AUTH_BASE_URL',
  defaultValue: 'https://nova3d.xyz',
);

// ── Product analytics (PostHog) ───────────────────────────────────────────────
//
// THIS REPO IS PUBLIC AND SELF-HOSTABLE. No PostHog credential is committed
// here or anywhere else in the tree, including web/index.html.
//
// `kPostHogKey` defaults to EMPTY, which makes `Analytics` a total no-op: no
// script init, no events, no session recording. A fork therefore never emits
// into anyone else's project and never needs a PostHog account to run the app.
//
// Supply the key at build time from your CI's environment, never from source:
//   flutter build web --release --dart-define=POSTHOG_KEY=$POSTHOG_KEY
//
// A PostHog project key is a write-only ingestion token (it cannot read data)
// and is visible in any production JS bundle by design. Keeping it out of the
// repo is about scraping and fork pollution, not secrecy: automated scanners
// harvest tokens from git within minutes, and git history is permanent.
const String kPostHogKey = String.fromEnvironment('POSTHOG_KEY');

/// Ingestion host. Defaults to PostHog US Cloud so a fork works out of the box.
///
/// Override it with a PostHog managed reverse proxy on your own domain if you
/// have one — a first-party host stops ad-blockers silently dropping events,
/// and it serves the SDK assets too. The default stays PostHog's public
/// endpoint so a fork talks to its own project directly.
const String kPostHogHost = String.fromEnvironment(
  'POSTHOG_HOST',
  defaultValue: 'https://us.i.posthog.com',
);

/// Pins posthog-js's behavioural defaults to a dated baseline, matching the
/// snippet PostHog generates in its setup instructions. Without it, upgrading
/// the SDK can silently change capture behaviour (autocapture, pageview mode).
/// Explicit options in `_initConfig` still win over anything this sets.
const String kPostHogDefaults = String.fromEnvironment(
  'POSTHOG_DEFAULTS',
  defaultValue: '2026-05-30',
);

/// Where "view recording" links point. Distinct from the ingestion host.
const String kPostHogUiHost = String.fromEnvironment(
  'POSTHOG_UI_HOST',
  defaultValue: 'https://us.posthog.com',
);

/// Captures user-authored content (prompt text, AI-edit descriptions, emails)
/// in event properties. Provider API keys are never captured regardless of
/// this flag — see `Analytics._scrub`. Build with
/// `--dart-define=CAPTURE_USER_CONTENT=false` for a metadata-only deployment.
const bool kCaptureUserContent = bool.fromEnvironment(
  'CAPTURE_USER_CONTENT',
  defaultValue: true,
);

/// Session-replay canvas snapshot rate. Flutter web renders to a canvas, so
/// these two values decide whether replays of the 3D editor are legible.
/// PostHog accepts 0–12 fps; quality is a decimal string in 0–1.
const int kReplayCanvasFps = int.fromEnvironment(
  'REPLAY_CANVAS_FPS',
  defaultValue: 6,
);

const String kReplayCanvasQuality = String.fromEnvironment(
  'REPLAY_CANVAS_QUALITY',
  defaultValue: '0.8',
);

/// Fraction of display resolution at which replay captures canvas frames
/// (0 < scale <= 1). Replay upscales back to the original size, so only
/// sharpness changes, never playback dimensions.
///
/// Left at 1.0 (posthog-js's own default) so the fidelity choice is exactly
/// what was asked for. Recorded byte volume scales with pixel *area*, so this
/// is the first knob to turn — ahead of fps — if replay gets expensive.
/// (String because Dart only provides String/int/bool `fromEnvironment`;
/// parsed at the single use site in `Analytics._initConfig`.)
const String kReplayCanvasResolutionScale = String.fromEnvironment(
  'REPLAY_CANVAS_RESOLUTION_SCALE',
  defaultValue: '1.0',
);

/// Surfaced as a super property on every event so regressions can be pinned to
/// a build. Bump with the pubspec version.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0',
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
