# SPDX-License-Identifier: MIT
"""Scene + WindowManager properties for the add-on.

Scene properties hold user *input* (prompt, model, reference images) and are
saved with the .blend. WindowManager properties hold transient *runtime* state
(status line, busy flag, cached Nova3D Credits count) and are not saved.
"""

import bpy

from . import constants
from .services import provider_access


class Nova3DReferenceImage(bpy.types.PropertyGroup):
    """One reference image path in the per-scene image list."""
    path: bpy.props.StringProperty(
        name="Path", subtype="FILE_PATH", description="Reference image file")


# Every string returned by the dynamic model callback lives in these module-level
# containers. Blender retains references to enum strings, so constructing them
# inside the callback can otherwise leave dangling strings and crash the UI.
_HOSTED_MODEL_ENUM_ITEMS = tuple(
    (option_id,
     f"{label} — {credits} credits" + (f" · {badge}" if badge else ""),
     f"Nova3D-hosted {label}; the live credit estimate is checked before generation",
     "FUND", index)
    for index, (option_id, label, _tier, credits, badge)
    in enumerate(constants.HOSTED_MODEL_OPTIONS, start=1)
)

_PROVIDER_MODEL_ENUM_ITEMS = {
    option_id: (
        option_id,
        f"{label} — your {constants.provider_for_option((option_id,)).title()} key",
        f"{label} billed directly by {constants.provider_for_option((option_id,)).title()}",
        "KEY_HLT", index,
    )
    for index, (option_id, label, _tier, _credits, _badge)
    in enumerate(constants.PROVIDER_MODEL_OPTIONS, start=101)
}

_PROVIDER_SETUP_ENUM_ITEM = (
    constants.PROVIDER_SETUP_OPTION_ID,
    "Add and test a provider key below",
    "Provider-key models appear after their key, funding, and access are verified",
    "ERROR", 999,
)


def available_model_options(context, access_mode=None):
    mode = access_mode or getattr(getattr(context, "scene", None),
                                  "nova3d_access_mode",
                                  constants.BILLING_NOVA3D_CREDITS)
    if mode != constants.BILLING_PROVIDER_KEY:
        return constants.HOSTED_MODEL_OPTIONS
    try:
        from .preferences import get_prefs
        return provider_access.available_provider_options(get_prefs(context))
    except Exception:
        return ()


def _model_enum_items(_self, context):
    mode = getattr(getattr(context, "scene", None), "nova3d_access_mode",
                   constants.BILLING_NOVA3D_CREDITS)
    if mode != constants.BILLING_PROVIDER_KEY:
        return _HOSTED_MODEL_ENUM_ITEMS
    options = available_model_options(context, mode)
    if not options:
        return (_PROVIDER_SETUP_ENUM_ITEM,)
    return tuple(_PROVIDER_MODEL_ENUM_ITEMS[option[0]] for option in options)


def ensure_valid_model_selection(context):
    scene = getattr(context, "scene", None)
    if scene is None or not hasattr(scene, "nova3d_model"):
        return
    mode = getattr(scene, "nova3d_access_mode", constants.BILLING_NOVA3D_CREDITS)
    options = available_model_options(context, mode)
    valid_ids = {option[0] for option in options}
    current = getattr(scene, "nova3d_model", "")
    if current in valid_ids:
        return
    if mode == constants.BILLING_NOVA3D_CREDITS:
        desired = constants.DEFAULT_MODEL_OPTION_ID
    else:
        desired = (options[0][0] if options else constants.PROVIDER_SETUP_OPTION_ID)
    try:
        scene.nova3d_model = desired
    except Exception:
        pass


def _access_mode_changed(_scene, context):
    scene = getattr(context, "scene", None)
    if scene is None:
        return
    if scene.nova3d_access_mode == constants.BILLING_NOVA3D_CREDITS:
        desired = constants.DEFAULT_MODEL_OPTION_ID
    else:
        options = available_model_options(context, constants.BILLING_PROVIDER_KEY)
        desired = (options[0][0] if options else constants.PROVIDER_SETUP_OPTION_ID)
    try:
        scene.nova3d_model = desired
    except Exception:
        pass


def register_properties():
    bpy.utils.register_class(Nova3DReferenceImage)

    scene = bpy.types.Scene
    scene.nova3d_prompt = bpy.props.StringProperty(
        name="Prompt",
        description="Describe the 3D model to generate (max 40 words)",
        default="",
    )
    scene.nova3d_access_mode = bpy.props.EnumProperty(
        name="Generation access",
        description="Use Nova3D Credits or a directly verified provider API key",
        items=(
            (constants.BILLING_NOVA3D_CREDITS, "Nova3D Credits",
             "Nova3D handles provider access and billing", "FUND", 1),
            (constants.BILLING_PROVIDER_KEY, "My API Key",
             "Use a verified Anthropic or OpenAI API key", "KEY_HLT", 2),
        ),
        default=constants.BILLING_NOVA3D_CREDITS,
        update=_access_mode_changed,
    )
    scene.nova3d_model = bpy.props.EnumProperty(
        name="Model",
        description="Which LLM writes the Blender program",
        items=_model_enum_items,
        # Dynamic EnumProperty callbacks require an integer default. Item 2 is
        # the hosted Claude Fable 5 recommendation.
        default=2,
    )
    scene.nova3d_images = bpy.props.CollectionProperty(type=Nova3DReferenceImage)
    scene.nova3d_images_index = bpy.props.IntProperty(name="Image", default=0)

    wm = bpy.types.WindowManager
    wm.nova3d_running = bpy.props.BoolProperty(default=False)
    wm.nova3d_signing_in = bpy.props.BoolProperty(default=False)
    wm.nova3d_status = bpy.props.StringProperty(default="")
    wm.nova3d_workflow_id = bpy.props.StringProperty(default="")
    wm.nova3d_credits = bpy.props.IntProperty(default=-1)  # -1 = unknown
    wm.nova3d_credits_busy = bpy.props.BoolProperty(default=False)
    wm.nova3d_last_dir = bpy.props.StringProperty(default="")
    wm.nova3d_pending = bpy.props.IntProperty(default=0)  # interrupted runs to resume
    wm.nova3d_conversation_id = bpy.props.StringProperty(default="")
    wm.nova3d_provider_test_busy = bpy.props.BoolProperty(default=False)
    wm.nova3d_provider_test_name = bpy.props.StringProperty(default="")
    # Service health: set when a probe cannot reach Nova3D (outage / no network).
    wm.nova3d_service_down = bpy.props.BoolProperty(default=False)
    # Update check (against GitHub Releases; independent of sign-in).
    wm.nova3d_update_available = bpy.props.BoolProperty(default=False)
    wm.nova3d_latest_version = bpy.props.StringProperty(default="")
    wm.nova3d_release_url = bpy.props.StringProperty(default="")
    wm.nova3d_updates_busy = bpy.props.BoolProperty(default=False)


def unregister_properties():
    scene = bpy.types.Scene
    for attr in ("nova3d_prompt", "nova3d_model", "nova3d_access_mode",
                 "nova3d_images", "nova3d_images_index"):
        if hasattr(scene, attr):
            delattr(scene, attr)

    wm = bpy.types.WindowManager
    for attr in ("nova3d_running", "nova3d_signing_in", "nova3d_status",
                 "nova3d_workflow_id", "nova3d_credits",
                 "nova3d_credits_busy", "nova3d_last_dir", "nova3d_pending",
                 "nova3d_conversation_id", "nova3d_provider_test_busy",
                 "nova3d_provider_test_name",
                 "nova3d_service_down", "nova3d_update_available",
                 "nova3d_latest_version", "nova3d_release_url",
                 "nova3d_updates_busy"):
        if hasattr(wm, attr):
            delattr(wm, attr)

    bpy.utils.unregister_class(Nova3DReferenceImage)
