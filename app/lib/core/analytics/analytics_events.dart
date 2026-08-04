// The Nova3D product analytics taxonomy.
//
// WHY A CONSTANTS FILE: PostHog groups by exact event-name string. A typo in a
// literal creates a silent second event that splits a funnel in half and is
// unfixable retroactively. Every capture site in the app must reference a
// constant from this file — never an inline string.
//
// NAMING RULES (follow these when adding events):
//   * `noun_verbed`, snake_case, past tense — `generation_succeeded`.
//   * The noun is the domain object, so events sort together alphabetically in
//     PostHog's event list: everything about generation starts with `generation_`.
//   * Properties are snake_case and stable. Prefer adding a property over
//     minting a near-duplicate event.
//   * Names starting with `$` are PostHog-reserved. Don't invent new ones.
//
// The taxonomy deliberately covers surfaces that are not instrumented for a
// specific question yet (sculpt tools, display modes, joint drags). They are
// cheap to send and impossible to backfill — the point is that when a question
// arrives in three months, the history already exists.

/// Event names. Referenced by every `Analytics.capture` call in the app.
abstract final class Ev {
  // ── Lifecycle ─────────────────────────────────────────────────────────────
  /// First frame reached. Carries boot timing + environment fingerprint.
  static const appBooted = 'app_booted';

  /// Manual pageview; posthog-js autocapture pageviews are disabled because
  /// GoRouter owns navigation and gives us the matched route pattern.
  static const pageview = r'$pageview';
  static const pageleave = r'$pageleave';

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const signUpStarted = 'sign_up_started';
  static const signUpSucceeded = 'user_signed_up';
  static const signUpFailed = 'sign_up_failed';
  static const signInStarted = 'sign_in_started';
  static const signInSucceeded = 'user_signed_in';
  static const signInFailed = 'sign_in_failed';
  static const signedOut = 'user_signed_out';
  static const passwordResetRequested = 'password_reset_requested';

  // ── Generation funnel (the core product loop) ─────────────────────────────
  /// User pressed generate. Fires BEFORE preflight, so the preflight drop-off
  /// rate is measurable.
  static const generationRequested = 'generation_requested';

  /// Readiness / credits / missing-key check refused to start the run.
  static const generationBlocked = 'generation_blocked';

  /// GraphFlow accepted the run and returned a workflow id.
  static const generationStarted = 'generation_started';

  /// One row per GraphFlow node transition. This is what turns the opaque
  /// "generating…" wait into a per-stage funnel (caption → codegen → build →
  /// build → review) with real stage durations.
  static const generationNodeChanged = 'generation_node_changed';

  /// The build stage did not succeed first time and the graph re-ran it.
  static const generationStageRetried = 'generation_stage_retried';

  static const generationSucceeded = 'generation_succeeded';
  static const generationFailed = 'generation_failed';
  static const generationRetried = 'generation_retried';
  static const generationResumed = 'generation_resumed';

  // ── Reference images / prompt composition ────────────────────────────────
  static const referenceImageAttached = 'reference_image_attached';
  static const referenceImageRemoved = 'reference_image_removed';
  static const referenceImageRejected = 'reference_image_rejected';
  static const promptLimitHit = 'prompt_limit_hit';
  static const modelOptionChanged = 'model_option_changed';

  // ── 3D editor (the code-native differentiator) ───────────────────────────
  static const viewerOpened = 'viewer_opened';
  static const viewerFullscreenToggled = 'viewer_fullscreen_toggled';
  static const meshSelected = 'mesh_selected';
  static const editorToolUsed = 'editor_tool_used';
  static const displayModeChanged = 'display_mode_changed';
  static const explodeViewUsed = 'explode_view_used';
  static const sculptStrokeApplied = 'sculpt_stroke_applied';
  static const transformApplied = 'transform_applied';
  static const materialApplied = 'material_applied';
  static const undoUsed = 'undo_used';
  static const redoUsed = 'redo_used';
  static const versionSwitched = 'version_switched';
  static const modelDownloaded = 'model_downloaded';
  static const cameraFramed = 'camera_framed';

  // ── AI edits (code-level mutations) ──────────────────────────────────────
  static const aiEditRequested = 'ai_edit_requested';
  static const aiEditSucceeded = 'ai_edit_succeeded';
  static const aiEditFailed = 'ai_edit_failed';

  // ── Articulation ─────────────────────────────────────────────────────────
  static const articulationJointMoved = 'articulation_joint_moved';
  static const articulationDemoToggled = 'articulation_demo_toggled';

  // ── Source code surface ──────────────────────────────────────────────────
  /// Interactions with the generated Blender script.
  static const codeViewed = 'code_viewed';
  static const codeCopied = 'code_copied';
  static const codeDownloaded = 'code_downloaded';

  // ── Texturing / UV ───────────────────────────────────────────────────────
  static const textureRequested = 'texture_requested';
  static const textureBlocked = 'texture_blocked';
  static const textureStarted = 'texture_started';
  static const textureNodeChanged = 'texture_node_changed';
  static const textureSucceeded = 'texture_succeeded';
  static const textureFailed = 'texture_failed';
  static const textureAssetsDownloaded = 'texture_assets_downloaded';

  static const uvMapsRequested = 'uv_maps_requested';
  static const uvMapsSucceeded = 'uv_maps_succeeded';
  static const uvMapsFailed = 'uv_maps_failed';
  static const uvMapsDownloaded = 'uv_maps_downloaded';

  // ── Showcase ─────────────────────────────────────────────────────────────
  static const showcaseViewed = 'showcase_viewed';
  static const showcaseTabChanged = 'showcase_tab_changed';
  static const showcaseItemOpened = 'showcase_item_opened';

  // ── Billing / credits ────────────────────────────────────────────────────
  static const subscriptionViewed = 'subscription_viewed';
  static const checkoutStarted = 'checkout_started';
  static const paymentSucceeded = 'payment_succeeded';
  static const creditsEstimated = 'credits_estimated';
  static const creditsInsufficient = 'credits_insufficient';

  // ── Provider keys (BYOK) — never carries key material ────────────────────
  static const apiKeySaved = 'api_key_saved';
  static const apiKeyRemoved = 'api_key_removed';
  static const apiKeyValidationFailed = 'api_key_validation_failed';

  // ── MCP ──────────────────────────────────────────────────────────────────
  static const mcpConnectViewed = 'mcp_connect_viewed';
  static const mcpKeyIssued = 'mcp_key_issued';
  static const mcpKeyCopied = 'mcp_key_copied';

  // ── Errors ───────────────────────────────────────────────────────────────
  /// PostHog error-tracking reserved event; emitted via captureException.
  static const exception = r'$exception';

  /// A handled, user-visible error surfaced in the UI (a red banner / snackbar).
  /// Distinct from `$exception`, which is an uncaught crash.
  static const errorShown = 'error_shown';
}

/// Property keys. Same rationale as [Ev]: PostHog treats property names as
/// exact strings, and a drifted name breaks every saved insight using it.
abstract final class Pr {
  // Identity / environment (mostly registered as super properties)
  static const appVersion = 'app_version';
  static const buildMode = 'build_mode';
  static const renderer = 'renderer';
  static const viewportW = 'viewport_width';
  static const viewportH = 'viewport_height';
  static const devicePixelRatio = 'device_pixel_ratio';
  static const bootMs = 'boot_ms';

  // Routing
  static const route = 'route';
  static const routePattern = 'route_pattern';
  static const previousRoute = 'previous_route';

  // Auth
  static const authMethod = 'auth_method';
  static const isVerified = 'is_verified';

  // Model routing
  static const modelOptionId = 'model_option_id';
  static const modelLabel = 'model_label';
  static const codeLlmProfile = 'code_llm_profile';
  static const codeLlmTier = 'code_llm_tier';
  static const provider = 'provider';
  static const billingMode = 'billing_mode';
  static const isByok = 'is_byok';
  static const workflowName = 'workflow_name';
  static const workflowId = 'workflow_id';

  // Prompt / inputs (full text — see kCaptureUserContent in constants.dart)
  static const prompt = 'prompt';
  static const promptLength = 'prompt_length';
  static const promptWordCount = 'prompt_word_count';
  static const hasReferenceImages = 'has_reference_images';
  static const imageCount = 'image_count';
  static const imageBytes = 'image_bytes';
  static const surface = 'surface';

  // Workflow progress
  static const node = 'node';
  static const nodeLabel = 'node_label';
  static const previousNode = 'previous_node';
  static const nodeElapsedMs = 'node_elapsed_ms';
  static const totalElapsedMs = 'total_elapsed_ms';
  static const durationMs = 'duration_ms';
  static const terminalNode = 'terminal_node';
  static const retryCount = 'retry_count';
  static const stageRetryCount = 'stage_retry_count';
  static const nodesVisited = 'nodes_visited';
  static const hadStageRetry = 'had_stage_retry';
  static const reviewOutcome = 'review_outcome';
  static const isResume = 'is_resume';

  // Results
  static const succeeded = 'succeeded';
  static const jointCount = 'joint_count';
  static const partCount = 'part_count';
  static const meshCount = 'mesh_count';
  static const triangleCount = 'triangle_count';
  static const glbBytes = 'glb_bytes';
  static const codeChars = 'code_chars';
  static const codeLines = 'code_lines';

  // Errors
  static const errorMessage = 'error_message';
  static const errorCategory = 'error_category';
  static const failureOrigin = 'failure_origin';
  static const retryable = 'retryable';
  static const reason = 'reason';
  static const statusCode = 'status_code';
  static const context = 'context';
  static const handled = 'handled';

  // Editor
  static const operation = 'operation';
  static const tool = 'tool';
  static const mode = 'mode';
  static const selectedMeshCount = 'selected_mesh_count';
  static const selectedMeshNames = 'selected_mesh_names';
  static const description = 'description';
  static const descriptionLength = 'description_length';
  static const jointName = 'joint_name';
  static const jointKind = 'joint_kind';
  static const axis = 'axis';
  static const versionIndex = 'version_index';
  static const versionCount = 'version_count';
  static const fromIndex = 'from_index';
  static const enabled = 'enabled';
  static const source = 'source';

  // Texture / UV
  static const resolution = 'resolution';
  static const atlasMode = 'atlas_mode';
  static const atlasCount = 'atlas_count';
  static const assetKind = 'asset_kind';
  static const assetCount = 'asset_count';

  // Billing
  static const credits = 'credits';
  static const creditsAvailable = 'credits_available';
  static const creditsRequired = 'credits_required';
  static const projectedMaxHold = 'projected_max_hold';
  static const authorizedBudget = 'authorized_budget';
  static const plan = 'plan';

  // Showcase
  static const showcaseTab = 'showcase_tab';
  static const itemId = 'item_id';
  static const itemTitle = 'item_title';

  // Person properties
  static const email = 'email';
  static const generationCount = 'generation_count';
  static const providersConfigured = 'providers_configured';
  static const hasAnyProviderKey = 'has_any_provider_key';
}

/// Events the Three.js editor iframe is permitted to emit via postMessage.
///
/// A postMessage is untrusted input — any page could post into the app window.
/// Without this allowlist an attacker could inject arbitrary event names and
/// poison the taxonomy. The bridge in `glb_viewer_web.dart` drops anything not
/// listed here, so adding a viewer event means adding it in two places on
/// purpose.
const Set<String> kViewerEvents = <String>{
  Ev.aiEditRequested,
  Ev.aiEditSucceeded,
  Ev.aiEditFailed,
  Ev.editorToolUsed,
  Ev.displayModeChanged,
  Ev.explodeViewUsed,
  Ev.materialApplied,
  Ev.meshSelected,
  Ev.modelDownloaded,
  Ev.undoUsed,
  Ev.redoUsed,
  Ev.versionSwitched,
  Ev.articulationJointMoved,
  Ev.uvMapsRequested,
};

/// Values for [Pr.reviewOutcome] — the three terminal shapes of the review
/// stage.
abstract final class ReviewOutcome {
  /// Review passed; the original export ships.
  static const pass = 'pass';

  /// Review produced an amended build that shipped in place of the original.
  static const amended = 'amended';

  /// An amend was attempted but did not ship; the original export is kept.
  static const originalKept = 'original_kept';
}

/// Values for [Pr.surface] — where in the UI an action originated.
abstract final class Surface {
  static const home = 'home';
  static const chat = 'chat';
  static const viewer = 'viewer';
  static const showcase = 'showcase';
  static const settings = 'settings';
}
