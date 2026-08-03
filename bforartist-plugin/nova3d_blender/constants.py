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
ADDON_VERSION = (1, 0, 1)
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
# Two initial-generation workflows, picked by the selected model option. Both are
# started the same way (`POST /run/state/<workflow>?request_id=...`); they differ
# only in the payload and in who pays:
#   * WORKFLOW_NAME      — billed in Nova3D credits. The payload carries NO
#     provider key; the backend resolves provider credentials from its own
#     environment. Gated by a /credits/estimate + balance preflight.
#   * BYOK_WORKFLOW_NAME — billed to the user's OWN provider account. The payload
#     carries `code_llm_provider` + `code_llm_api_key`, and NO credit preflight
#     runs (the run costs 0 Nova3D credits).
# This mirrors `_initialGenerationWorkflow` / `_generationPayload` in the web
# client (`app/lib/features/cad/data/cad_service.dart`).
WORKFLOW_NAME = "sketch_to_3d_v2"
BYOK_WORKFLOW_NAME = "sketch_to_3d_byok_v2"
CODE_LLM_PROFILE = "nova3d_code_generation"
UV_WORKFLOW_NAME = "generate_uv_maps"

# Terminal carriers the result endpoint may return for sketch_to_3d_v2.
GENERATION_RETURN_NODES = (
    "final_validated_correction",
    "final_latest_valid",
    "fail_generation",
)
# sketch_to_3d_byok_v2 adds one more terminal carrier: the node the workflow
# exits through when the supplied provider key is missing or rejected. The web
# client requests it too (`_generationReturnNodes`).
BYOK_GENERATION_RETURN_NODES = GENERATION_RETURN_NODES + ("require_byok_api_key",)


def return_nodes_for(workflow_name):
    """Terminal carriers to request when starting *workflow_name*."""
    if workflow_name == BYOK_WORKFLOW_NAME:
        return BYOK_GENERATION_RETURN_NODES
    return GENERATION_RETURN_NODES

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


# ── Model options ────────────────────────────────────────────────────────────
# Every option is a 6-tuple: (id, label, code_llm_tier, credits, badge, provider).
#   * `provider` == ""  → paid-credit option, run on WORKFLOW_NAME.
#   * `provider` != ""  → BYOK option, run on BYOK_WORKFLOW_NAME using the user's
#     own key for that provider. `credits` is 0 (BYOK never touches the wallet).
# `credits` is a display hint only — the authoritative hold comes from
# POST /credits/estimate at generation time (paid options only).
MODEL_OPTIONS = (
    ("credits_gemini_3_1_pro_google", "Gemini 3.1 Pro Preview",
     "gemini_3_1_pro_google", 12, "Fastest", ""),
    ("credits_claude_sonnet_4_6_anthropic", "Claude Sonnet 4.6",
     "claude_sonnet_4_6_anthropic", 15, "", ""),
    ("credits_claude_fable_5_anthropic", "Claude Fable 5",
     "claude_fable_5_anthropic", 60, "", ""),
    ("credits_claude_opus_5_anthropic", "Claude Opus 5",
     "claude_opus_5_anthropic", 25, "", ""),
    ("credits_gpt_5_6_sol_openrouter", "GPT-5.6 Sol",
     "gpt_5_6_sol_openrouter", 30, "", ""),
    ("credits_gpt_5_5_openrouter", "GPT-5.5",
     "gpt_5_5_openrouter", 28, "Recommended", ""),
)
DEFAULT_MODEL_OPTION_ID = "credits_gemini_3_1_pro_google"

# Providers a BYOK key can be stored for: (id, label, expected key prefix). The
# ids are the exact `code_llm_provider` values the payload sends, matching
# `GenerationProvider` in the web client.
BYOK_PROVIDERS = (
    ("gemini", "Gemini", "AIza / AQ."),
    ("anthropic", "Anthropic", "sk-ant-"),
    ("openai", "OpenAI", "sk-"),
    ("openrouter", "OpenRouter", "sk-or-"),
)

# BYOK options. Ids and tiers match the web client's BYOK catalog
# (`generation_model_option.dart`) so a Blender-started BYOK run appears in web
# history under the same model identity a browser-started one would.
BYOK_MODEL_OPTIONS = (
    ("gemini_gemini", "Gemini 3.1 Pro Preview",
     "gemini_3_1_pro_google", 0, "", "gemini"),
    ("anthropic_claude_sonnet", "Claude Sonnet 4.6",
     "claude_sonnet_4_6_anthropic", 0, "", "anthropic"),
    ("anthropic_claude_fable_5", "Claude Fable 5",
     "claude_fable_5_anthropic", 0, "", "anthropic"),
    ("anthropic_claude_opus_5", "Claude Opus 5",
     "claude_opus_5_anthropic", 0, "", "anthropic"),
    ("openai_gpt_5_6_sol", "GPT-5.6 Sol",
     "gpt_5_6_sol_openai", 0, "", "openai"),
    ("openai_gpt55", "GPT-5.5",
     "gpt_5_5_openai", 0, "", "openai"),
    ("openrouter_claude_fable_5", "Claude Fable 5",
     "claude_fable_5_openrouter", 0, "", "openrouter"),
    ("openrouter_claude_opus_5", "Claude Opus 5",
     "claude_opus_5_openrouter", 0, "", "openrouter"),
    ("openrouter_gpt56_sol", "GPT-5.6 Sol",
     "gpt_5_6_sol_openrouter", 0, "", "openrouter"),
    ("openrouter_gpt55", "GPT-5.5",
     "gpt_5_5_openrouter", 0, "", "openrouter"),
    ("openrouter_gemini", "Gemini 3.1 Pro Preview",
     "gemini_3_1_pro_openrouter", 0, "", "openrouter"),
)

ALL_MODEL_OPTIONS = MODEL_OPTIONS + BYOK_MODEL_OPTIONS


def normalize_model_option(option):
    """Coerce *option* to the canonical 6-tuple.

    Pending records written by an older build stored a 5-tuple (no `provider`
    slot). Padding here keeps `Resume` working across an upgrade instead of
    raising a ValueError while unpacking.
    """
    values = tuple(option or ())[:6]
    padding = ("", "", "", 0, "", "")[len(values):]
    return values + padding


def model_option_by_id(option_id):
    """Return the (id, label, tier, credits, badge, provider) tuple for *option_id*."""
    for option in ALL_MODEL_OPTIONS:
        if option[0] == option_id:
            return option
    return MODEL_OPTIONS[0]


def is_byok_option(option):
    """True when *option* runs on the caller's own provider key."""
    return bool(normalize_model_option(option)[5])


def workflow_for_option(option):
    """The GraphFlow workflow that *option* must be started on."""
    return BYOK_WORKFLOW_NAME if is_byok_option(option) else WORKFLOW_NAME


def byok_provider_label(provider_id):
    """Human-readable name for a `code_llm_provider` id."""
    for pid, label, _prefix in BYOK_PROVIDERS:
        if pid == provider_id:
            return label
    return provider_id or "provider"


# ── BYOK minimum balance guidance ────────────────────────────────────────────
# A paid option can advertise an exact credit cost because Nova3D holds those
# credits up front. A BYOK run has no such gate — the provider bills as it goes,
# and a key that runs dry mid-run wastes whatever was already spent. So instead
# of a price we advertise the balance to keep available on the provider account.
# The cheaper tiers need less; everything else uses the higher figure.
BYOK_LOW_COST_TIERS = frozenset({
    "gemini_3_1_pro_google",
    "gemini_3_1_pro_openrouter",
    "gpt_5_5_openai",
    "gpt_5_5_openrouter",
})
BYOK_MIN_BALANCE_LOW_USD = 5
BYOK_MIN_BALANCE_USD = 10


def byok_min_balance_usd(option):
    """Dollars to keep available on the provider account for *option*."""
    tier = normalize_model_option(option)[2]
    if tier in BYOK_LOW_COST_TIERS:
        return BYOK_MIN_BALANCE_LOW_USD
    return BYOK_MIN_BALANCE_USD


# Shortest key we will accept, matching the web client's own length guard.
MIN_BYOK_KEY_LENGTH = 16


def detect_byok_provider(api_key):
    """Identify which provider *api_key* belongs to, from its prefix.

    Lets one paste field serve all four providers. The rules mirror
    `_formatError` in the web client's `api_key_service.dart`, including the
    ORDER: OpenAI's plain `sk-` is only matched after Anthropic's `sk-ant-` and
    OpenRouter's `sk-or-` have been ruled out, since both are also `sk-` keys.

    Returns a provider id, or "" when the key is unrecognised or too short.
    """
    key = (api_key or "").strip()
    if len(key) < MIN_BYOK_KEY_LENGTH:
        return ""
    # Google issues Gemini keys in two shapes: the long-standing `AIza…` and the
    # newer `AQ.…` handed out by AI Studio. Both are live, so both are accepted —
    # matching only `AIza` (as the web client still does) rejects valid keys.
    if key.startswith("AIza") or key.startswith("AQ."):
        return "gemini"
    if key.startswith("sk-ant-"):
        return "anthropic"
    if key.startswith("sk-or-"):
        return "openrouter"
    if key.startswith("sk-"):
        return "openai"
    return ""


BYOK_KEY_FORMAT_HINT = (
    "Unrecognised key. Expected AIza…/AQ.… (Gemini), sk-ant-… (Anthropic), "
    "sk-or-… (OpenRouter) or sk-… (OpenAI).")


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
    # sketch_to_3d_byok_v2 only.
    "require_byok_api_key": "Checking provider key...",
}

# ── Running indicator ────────────────────────────────────────────────────────
# The backend reports which NODE a run is on, never a percentage, and the
# pipeline loops (retry gate -> repair -> back to run_blender). Any derived
# percentage would therefore stall or run backwards, so the panel shows an
# indeterminate rotating indicator instead: it only claims "still working",
# which is the one thing the status endpoint actually tells us.
SPINNER_FRAMES = ("|", "/", "-", "\\")
SPINNER_PERIOD_SECONDS = 0.8   # one full rotation

# Generations routinely run for many minutes. Saying so up front stops the run
# from looking wedged while the model is being built and repaired.
LONG_RUN_NOTICE = "Can take 10+ minutes. Blender stays usable."

# sketch_to_3d_byok_v2 can finish with geometry but WITHOUT the validation pass —
# typically when the caller's provider credit ran out part-way. That is a partial
# success, not a failure: the model is delivered and imported, but the user has
# to be told it was never checked. Used when the result carries a model plus a
# failure/warning message, and the backend supplied no wording of its own.
UNVALIDATED_MODEL_NOTICE = (
    "Model generated, but validation was not completed — check the mesh.")


def spinner_frame(phase):
    """Spinner glyph for *phase*, a 0.0–1.0 position in the rotation."""
    index = int(phase * len(SPINNER_FRAMES)) % len(SPINNER_FRAMES)
    return SPINNER_FRAMES[index]


# Workflow runtime.state values that mean "stop polling".
TERMINAL_STATES = frozenset({
    "completed", "succeeded", "success",
    "budget_exhausted", "failed", "terminated",
    "cancelled", "timed_out", "timeout",
})
# Node ids that also signal completion even if runtime.state lags behind.
#
# `require_byok_api_key` is deliberately NOT here. It looks like a terminal
# carrier — the BYOK workflow can exit through it — but on a healthy run it is
# just a pass-through gate visited early, seconds after the workflow starts.
# Treating it as terminal made polling stop almost immediately and jump to
# /result, which then blocked for the entire generation: no progress updates,
# and a run longer than RESULT_HTTP_TIMEOUT would have failed outright. When the
# workflow really does exit through it, runtime.state goes terminal anyway and
# TERMINAL_STATES catches it.
TERMINAL_NODES = frozenset({
    "final_latest_valid", "final_validated_correction", "fail_generation",
})

# Object/collection naming used to group + auto-hide generations in the scene.
COLLECTION_PREFIX = "Nova3D_"
# Custom property tag written on collections this add-on creates.
GENERATED_TAG = "nova3d_generated"

CLIENT_NAME = "blender-plugin"
