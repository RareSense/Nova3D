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
# Nova3D Credits checkout. Same account and Stripe as the web app.
DEFAULT_WEB_BASE_URL = "https://app.nova3d.xyz"

API_KEY_PATH = "/api-key"        # where users create their n3d_ key
SUBSCRIPTION_PATH = "/subscription"  # Nova3D Credits checkout

# ── Add-on version + update check ────────────────────────────────────────────
# Single source of truth for comparisons. KEEP IN SYNC with the version in
# blender_manifest.toml and bl_info (__init__.py) when you cut a release.
ADDON_VERSION = (1, 2, 0)
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
PAID_WORKFLOW_NAME = "sketch_to_3d_v2"
BYOK_WORKFLOW_NAME = "sketch_to_3d_byok_v2"
# Backward-compatible alias for integrations that imported the original name.
WORKFLOW_NAME = PAID_WORKFLOW_NAME
CODE_LLM_PROFILE = "nova3d_code_generation"
UV_WORKFLOW_NAME = "generate_uv_maps"
BILLING_NOVA3D_CREDITS = "nova3d_credits"
BILLING_PROVIDER_KEY = "provider_key"

# Direct-provider setup. Provider keys are created and funded on the provider's
# own site; Nova3D has no balance API for ordinary user keys, so the add-on
# links users to the authoritative pages and verifies real model access before
# a workflow is started.
PROVIDER_ANTHROPIC = "anthropic"
PROVIDER_OPENAI = "openai"
ANTHROPIC_KEYS_URL = "https://platform.claude.com/settings/keys"
ANTHROPIC_BILLING_URL = "https://platform.claude.com/settings/billing"
OPENAI_KEYS_URL = "https://platform.openai.com/api-keys"
OPENAI_BILLING_URL = "https://platform.openai.com/settings/organization/billing"
OPENAI_MODEL_ACCESS_URL = "https://platform.openai.com/settings/organization/limits"
WEB_CHAT_PATH = "/chat"
RECOMMENDED_PROVIDER_BALANCE_USD = 20

# Terminal carriers the result endpoint may return for sketch_to_3d_v2.
GENERATION_RETURN_NODES = (
    "final_validated_correction",
    "final_latest_valid",
    "fail_generation",
    "fail_llm_generation",
)
BYOK_GENERATION_RETURN_NODES = GENERATION_RETURN_NODES + (
    "require_byok_api_key",
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


# ── Model options ────────────────────────────────────────────────────────────
# Every option keeps the legacy five-field shape used by history/project files:
# (id, label, code_llm_tier, Nova3D Credits, badge). Provider and provider model
# IDs live in maps below, keeping credentials/routing out of display strings.
# The displayed hosted credit amount is only a hint; /credits/estimate remains
# authoritative at runtime.
HOSTED_MODEL_OPTIONS = (
    ("credits_claude_opus_5_openrouter", "Claude Opus 5",
     "claude_opus_5_anthropic", 40, ""),
    ("credits_claude_fable_5_anthropic", "Claude Fable 5",
     "claude_fable_5_anthropic", 60, "Recommended"),
    ("credits_gpt_5_6_sol_openrouter", "GPT-5.6 Sol",
     "gpt_5_6_sol_openrouter", 30, ""),
    ("credits_gpt_5_5_openrouter", "GPT-5.5",
     "gpt_5_5_openrouter", 28, ""),
)

PROVIDER_MODEL_OPTIONS = (
    ("byok_claude_fable_5_anthropic", "Claude Fable 5",
     "claude_fable_5_anthropic", 0, "Anthropic"),
    ("byok_gpt_5_6_sol_openai", "GPT-5.6 Sol",
     "gpt_5_6_sol_openai", 0, "OpenAI"),
    ("byok_gpt_5_5_openai", "GPT-5.5",
     "gpt_5_5_openai", 0, "OpenAI"),
)

# Backward-compatible alias for code that imports the old hosted catalogue.
MODEL_OPTIONS = HOSTED_MODEL_OPTIONS
DEFAULT_MODEL_OPTION_ID = "credits_claude_fable_5_anthropic"
DEFAULT_PROVIDER_OPTION_ID = "byok_claude_fable_5_anthropic"
PROVIDER_SETUP_OPTION_ID = "provider_setup_required"

PROVIDER_BY_OPTION_ID = {
    "byok_claude_fable_5_anthropic": PROVIDER_ANTHROPIC,
    "byok_gpt_5_6_sol_openai": PROVIDER_OPENAI,
    "byok_gpt_5_5_openai": PROVIDER_OPENAI,
}

PROVIDER_MODEL_ID_BY_OPTION_ID = {
    "byok_claude_fable_5_anthropic": "claude-fable-5",
    "byok_gpt_5_6_sol_openai": "gpt-5.6-sol",
    "byok_gpt_5_5_openai": "gpt-5.5",
}


def model_option_by_id(option_id, *, access_mode=None):
    """Return the (id, label, tier, credits, badge) tuple for *option_id*."""
    options = HOSTED_MODEL_OPTIONS + PROVIDER_MODEL_OPTIONS
    for option in options:
        if option[0] == option_id:
            return option
    fallback_id = (DEFAULT_PROVIDER_OPTION_ID
                   if access_mode == BILLING_PROVIDER_KEY
                   else DEFAULT_MODEL_OPTION_ID)
    for option in options:
        if option[0] == fallback_id:
            return option
    return options[0]


def provider_for_option(model_option):
    """Return ``anthropic``/``openai`` for a provider-key option, else None."""
    option_id = model_option[0] if model_option else ""
    return PROVIDER_BY_OPTION_ID.get(option_id)


def provider_model_id_for_option(model_option):
    option_id = model_option[0] if model_option else ""
    return PROVIDER_MODEL_ID_BY_OPTION_ID.get(option_id)


def is_provider_option(model_option):
    return provider_for_option(model_option) is not None


def provider_options(provider=None):
    if not provider:
        return PROVIDER_MODEL_OPTIONS
    return tuple(
        option for option in PROVIDER_MODEL_OPTIONS
        if provider_for_option(option) == provider
    )


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
    "fail_llm_generation": "Model provider failed.",
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
    "fail_llm_generation",
})

# Object/collection naming used to group + auto-hide generations in the scene.
COLLECTION_PREFIX = "Nova3D_"
# Custom property tag written on collections this add-on creates.
GENERATED_TAG = "nova3d_generated"

CLIENT_NAME = "blender-plugin"
