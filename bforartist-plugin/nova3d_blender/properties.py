# SPDX-License-Identifier: MIT
"""Scene + WindowManager properties for the add-on.

Scene properties hold user *input* (prompt, model, reference images) and are
saved with the .blend. WindowManager properties hold transient *runtime* state
(status line, busy flag, cached credit count) and are intentionally not saved.
"""

import bpy

from . import constants, preferences


class Nova3DReferenceImage(bpy.types.PropertyGroup):
    """One reference image path in the per-scene image list."""
    path: bpy.props.StringProperty(
        name="Path", subtype="FILE_PATH", description="Reference image file")


def _byok_enum_item(option):
    """One BYOK dropdown entry: (identifier, label, tooltip).

    The `$N+` tag is the BYOK counterpart of the paid options' credit cost: not
    a price Nova3D charges, but the balance to keep on the provider account so
    the run does not stall part-way through.
    """
    option_id, label, _tier, _credits, _badge, provider = option
    provider_label = constants.byok_provider_label(provider)
    minimum = constants.byok_min_balance_usd(option)
    return (option_id,
            f"{label} — {provider_label} · ${minimum}+",
            f"{label}: runs on your own {provider_label} API key. "
            f"Keep at least ${minimum} of credit available on that account — "
            f"Nova3D credits are not used")


def _paid_enum_item(option):
    """One credits dropdown entry: (identifier, label, tooltip)."""
    option_id, label, _tier, credits, badge, _provider = option
    return (option_id,
            f"{label} — {credits} credits" + (f" ({badge})" if badge else ""),
            f"{label}: {credits} credits")


# Blender does NOT keep its own reference to the strings an items callback
# returns, so a list built fresh on each call can be garbage-collected while the
# UI still points at it — the well-known enum-callback crash. The documented
# workaround is to keep a strong module-level reference to the list we hand back,
# which is what `_BYOK_ITEMS_CACHE` is for. Never return a temporary.
_BYOK_ITEMS_CACHE = []

# The credits list is fixed, so it stays a plain static list.
_PAID_ENUM_ITEMS = [_paid_enum_item(option) for option in constants.MODEL_OPTIONS]

# Shown when no provider key has been added yet. An items callback must never
# return an empty list (that is itself a crash risk), so this placeholder stands
# in — the panel hides the dropdown entirely in that state, and
# `NOVA3D_OT_generate` refuses to run it.
BYOK_PLACEHOLDER_ID = "none"
_BYOK_PLACEHOLDER = [(BYOK_PLACEHOLDER_ID, "No API key added yet",
                      "Paste a provider API key above to unlock its models")]


def _byok_model_items(self, context):
    """BYOK dropdown contents: only models whose provider key is saved."""
    global _BYOK_ITEMS_CACHE

    # Runs on every redraw and must never raise — a failing items callback
    # breaks the whole panel. Trouble reading preferences just means "no keys".
    try:
        prefs = preferences.get_prefs(context) if context else None
    except Exception:  # noqa: BLE001 - defensive; the UI must keep drawing
        prefs = None

    unlocked = [
        _byok_enum_item(option)
        for option in constants.BYOK_MODEL_OPTIONS
        if prefs and preferences.byok_key_for(prefs, option[5])
    ]

    _BYOK_ITEMS_CACHE = unlocked or list(_BYOK_PLACEHOLDER)
    return _BYOK_ITEMS_CACHE


def _select_byok(self, context):
    """Picking a your-key model makes that the section Generate will use."""
    if self.nova3d_byok_model != BYOK_PLACEHOLDER_ID:
        self.nova3d_billing = "byok"


def _select_paid(self, context):
    """Picking a credits model makes that the section Generate will use."""
    self.nova3d_billing = "credits"


def register_properties():
    bpy.utils.register_class(Nova3DReferenceImage)

    scene = bpy.types.Scene
    scene.nova3d_prompt = bpy.props.StringProperty(
        name="Prompt",
        description="Describe the 3D model to generate (max 40 words)",
        default="",
    )
    # Which of the two sections Generate will use. Set automatically whenever the
    # user picks a model in either section, so there is no separate mode switch.
    scene.nova3d_billing = bpy.props.EnumProperty(
        name="Billing",
        description="Whether Generate uses your own API key or Nova3D credits",
        items=[
            ("byok", "Your API Key", "Run on your own provider key — no credits"),
            ("credits", "Nova3D Credits", "Run on Nova3D credits"),
        ],
        default="credits",
    )
    # No `default=` on the BYOK enum — Blender forbids it when `items` is a
    # callback. The first unlocked model is used instead.
    scene.nova3d_byok_model = bpy.props.EnumProperty(
        name="Model",
        description="Model to run on your own API key (costs no Nova3D credits)",
        items=_byok_model_items,
        update=_select_byok,
    )
    scene.nova3d_paid_model = bpy.props.EnumProperty(
        name="Model",
        description="Model to run on Nova3D credits",
        items=_PAID_ENUM_ITEMS,
        default=constants.DEFAULT_MODEL_OPTION_ID,
        update=_select_paid,
    )
    scene.nova3d_images = bpy.props.CollectionProperty(type=Nova3DReferenceImage)
    scene.nova3d_images_index = bpy.props.IntProperty(name="Image", default=0)

    wm = bpy.types.WindowManager
    # Transient paste field for a provider key. Lives on the WindowManager (not
    # the Scene) so a key in flight is never saved into the .blend; the operator
    # moves it into preferences and clears this immediately.
    wm.nova3d_key_input = bpy.props.StringProperty(
        name="API Key", default="", subtype="PASSWORD",
        description="Paste a Gemini, Anthropic, OpenAI or OpenRouter key — the "
                    "provider is detected automatically")
    # How the last finished run ended, so the status box can style itself:
    # "" (nothing yet) | "ok" | "warn" (delivered, but not fully validated)
    # | "error". Without this the box shows a green tick on every outcome,
    # including failures.
    wm.nova3d_outcome = bpy.props.StringProperty(default="")
    wm.nova3d_running = bpy.props.BoolProperty(default=False)
    wm.nova3d_signing_in = bpy.props.BoolProperty(default=False)
    wm.nova3d_status = bpy.props.StringProperty(default="")
    wm.nova3d_workflow_id = bpy.props.StringProperty(default="")
    wm.nova3d_credits = bpy.props.IntProperty(default=-1)  # -1 = unknown
    wm.nova3d_credits_busy = bpy.props.BoolProperty(default=False)
    wm.nova3d_last_dir = bpy.props.StringProperty(default="")
    wm.nova3d_pending = bpy.props.IntProperty(default=0)  # interrupted runs to resume
    # Service health: set when a probe cannot reach Nova3D (outage / no network).
    wm.nova3d_service_down = bpy.props.BoolProperty(default=False)
    # Update check (against GitHub Releases; independent of sign-in).
    wm.nova3d_update_available = bpy.props.BoolProperty(default=False)
    wm.nova3d_latest_version = bpy.props.StringProperty(default="")
    wm.nova3d_release_url = bpy.props.StringProperty(default="")
    wm.nova3d_updates_busy = bpy.props.BoolProperty(default=False)


def unregister_properties():
    scene = bpy.types.Scene
    for attr in ("nova3d_prompt", "nova3d_billing", "nova3d_byok_model",
                 "nova3d_paid_model", "nova3d_images",
                 "nova3d_images_index"):
        if hasattr(scene, attr):
            delattr(scene, attr)

    wm = bpy.types.WindowManager
    for attr in ("nova3d_key_input", "nova3d_outcome",
                 "nova3d_running", "nova3d_signing_in", "nova3d_status",
                 "nova3d_workflow_id", "nova3d_credits",
                 "nova3d_credits_busy", "nova3d_last_dir", "nova3d_pending",
                 "nova3d_service_down", "nova3d_update_available",
                 "nova3d_latest_version", "nova3d_release_url",
                 "nova3d_updates_busy"):
        if hasattr(wm, attr):
            delattr(wm, attr)

    bpy.utils.unregister_class(Nova3DReferenceImage)
