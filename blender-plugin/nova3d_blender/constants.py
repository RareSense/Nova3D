# SPDX-License-Identifier: MIT
"""Static configuration for the Nova3D Blender add-on.

Everything here mirrors the contract the official Flutter web client uses
(`app/lib/core/constants.dart`, `generation_model_option.dart`,
`sketch_to_3d_v2_frontend_integration.md`). The add-on talks to the SAME hosted
GraphFlow API the web app calls — there are no Blender-specific backend routes.

Nothing in this module imports `bpy`, so it is safe to import from worker
threads.
"""

# ── Base URLs (overridable in add-on Preferences) ────────────────────────────
# A single API base covers every call the plugin makes: /conversations,
# /credits, /run/state, /status, /result, /workflow/readiness all live under it.
DEFAULT_API_BASE_URL = "https://nova3d.xyz/api"
# Web base hosts the browser-only pages: account/API-key creation and the Stripe
# subscription/credits checkout. Same account, same Stripe as the web app.
DEFAULT_WEB_BASE_URL = "https://app.nova3d.xyz"

API_KEY_PATH = "/api-key"        # where users create their n3d_ key
SUBSCRIPTION_PATH = "/subscription"  # Stripe credits checkout

# ── Add-on version + update check ────────────────────────────────────────────
# Single source of truth for comparisons. KEEP IN SYNC with the version in
# blender_manifest.toml and bl_info (__init__.py) when you cut a release.
ADDON_VERSION = (1, 0, 0)
ADDON_VERSION_STR = ".".join(str(part) for part in ADDON_VERSION)
# Public GitHub releases — read-only, unauthenticated, used only to tell the
# user when a newer build exists. Releases are tagged `blender-plugin-v<x.y.z>`.
GITHUB_RELEASES_API = "https://api.github.com/repos/RareSense/Nova3D/releases"
RELEASES_PAGE_URL = "https://github.com/RareSense/Nova3D/releases"
RELEASE_TAG_PREFIX = "blender-plugin-v"
UPDATE_HTTP_TIMEOUT = 15.0

# ── Browser ("Sign in with Google") auth ─────────────────────────────────────
# Reuses the hosted MCP browser-login flow, so no backend changes are needed:
#   1. open <web>/mcp/connect?state=..&port=..  (user signs in with Google)
#   2. the app redirects to http://127.0.0.1:<port>/?code=..&state=..
#   3. swap the one-time code for an n3d_ token at <api>/mcp/session/exchange
MCP_CONNECT_PATH = "/mcp/connect"
SESSION_EXCHANGE_PATH = "/mcp/session/exchange"
SIGN_IN_TIMEOUT_SECONDS = 300    # how long to wait for the browser callback
# Sent as `client_name` to the connect page so it reads "Continue in Blender"
# instead of the generic "your MCP client".
CLIENT_DISPLAY_NAME = "Blender"

# ── Workflow contract ────────────────────────────────────────────────────────
# Credits-only initial generation. BYOK (`sketch_to_3d_byok_v2`) is intentionally
# NOT supported by this plugin — generations always use the paid-credit workflow.
WORKFLOW_NAME = "sketch_to_3d_v2"
CODE_LLM_PROFILE = "nova3d_code_generation"
UV_WORKFLOW_NAME = "generate_uv_maps"

# Terminal carriers the result endpoint may return for sketch_to_3d_v2.
GENERATION_RETURN_NODES = (
    "final_validated_correction",
    "final_latest_valid",
    "fail_generation",
)

# ── Input limits (identical to the web client) ───────────────────────────────
MAX_REFERENCE_IMAGES = 3
MAX_REFERENCE_IMAGE_BYTES = 8 * 1024 * 1024  # 8 MB before resize
MAX_REFERENCE_IMAGE_DIMENSION = 512          # longest side, preserve aspect ratio
MAX_PROMPT_WORDS = 40

# ── Polling cadence ──────────────────────────────────────────────────────────
STATUS_POLL_SECONDS = 3.0          # gentle, matches the web client
STATUS_HTTP_TIMEOUT = 30.0
RESULT_HTTP_TIMEOUT = 300.0        # results block until the workflow finishes
START_HTTP_TIMEOUT = 120.0
# Hard ceiling so a wedged workflow can never poll forever (backend caps at 7200).
MAX_GENERATION_SECONDS = 7200
# UV atlases run AFTER the model is delivered, as background best-effort work, so
# they get a much tighter ceiling than a full generation: a wedged UV workflow
# must never keep the worker thread alive for hours.
UV_MAX_SECONDS = 900

# A freshly accepted (202) workflow can briefly 404 on /status until Temporal
# registers it. We tolerate that only this long; if it never becomes visible the
# start truly failed.
START_VISIBLE_GRACE_SECONDS = 90
# Once a workflow HAS been seen running, this many consecutive "not found"
# responses means it terminated/aborted on the backend without a result (e.g. a
# hard fail node whose error escaped the workflow). We then stop and report a
# failure instead of polling indefinitely. 4 × 3s ≈ 12s of confirmation.
MISSING_AFTER_ALIVE_LIMIT = 4
# Transient network errors (DNS blip, dropped connection, gateway 502/503/504)
# are EXPECTED across a multi-minute generation and must never abort polling.
# We keep retrying through them and only give up after this many consecutive
# failures with no contact at all. 60 × 3s ≈ 3 minutes of sustained outage.
LOST_CONNECTION_LIMIT = 60


# ── Paid-credit model options ────────────────────────────────────────────────
# (id, label, code_llm_tier, credits, badge). `credits` is a display hint only —
# the authoritative hold comes from POST /credits/estimate at generation time.
MODEL_OPTIONS = (
    ("credits_gemini_3_1_pro_google", "Gemini 3.1 Pro Preview",
     "gemini_3_1_pro_google", 12, "Fastest"),
    ("credits_claude_sonnet_4_6_anthropic", "Claude Sonnet 4.6",
     "claude_sonnet_4_6_anthropic", 15, ""),
    ("credits_claude_opus_4_8_anthropic", "Claude Opus 4.8",
     "claude_opus_4_8_anthropic", 25, ""),
    ("credits_gpt_5_5_openrouter", "GPT-5.5",
     "gpt_5_5_openrouter", 28, "Recommended"),
)
DEFAULT_MODEL_OPTION_ID = "credits_gemini_3_1_pro_google"


def model_option_by_id(option_id):
    """Return the (id, label, tier, credits, badge) tuple for *option_id*."""
    for option in MODEL_OPTIONS:
        if option[0] == option_id:
            return option
    return MODEL_OPTIONS[0]


# ── Human-readable progress labels, keyed by GraphFlow node id ───────────────
# Mirrors WorkflowStatus._nodeLabels in the web client so the in-Blender status
# line reads exactly like the app's progress card.
NODE_PROGRESS_LABELS = {
    "caption_prompt": "Reading your reference image...",
    "caption_llm": "Understanding the reference image...",
    "generation_prompt": "Preparing the 3D generation prompt...",
    "code_generation_llm": "Writing the Blender scene...",
    "run_blender": "Building and exporting the 3D model...",
    "blender_retry_gate": "Checking the generated model...",
    "build_repair_prompt": "Preparing an automatic repair...",
    "repair_llm": "Repairing the Blender script...",
    "capture_validation_screenshots": "Capturing validation views...",
    "validation_prompt": "Preparing model validation...",
    "validation_llm": "Reviewing the generated model...",
    "validation_result_parser": "Finalizing the model...",
    "validation_correction_blender": "Applying validation fixes...",
    "final_latest_valid": "Finalizing the model...",
    "final_validated_correction": "Finalizing the corrected model...",
    "fail_generation": "Generation failed.",
}

# Workflow runtime.state values that mean "stop polling".
TERMINAL_STATES = frozenset({
    "completed", "succeeded", "success",
    "budget_exhausted", "failed", "terminated",
    "cancelled", "timed_out", "timeout",
})
# Node ids that also signal completion even if runtime.state lags behind.
TERMINAL_NODES = frozenset({
    "final_latest_valid", "final_validated_correction", "fail_generation",
})

# Object/collection naming used to group + auto-hide generations in the scene.
COLLECTION_PREFIX = "Nova3D_"
# Custom property tag written on collections this add-on creates.
GENERATED_TAG = "nova3d_generated"

CLIENT_NAME = "blender-plugin"
