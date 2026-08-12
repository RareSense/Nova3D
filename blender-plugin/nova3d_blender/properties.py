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
     label + (f" · {badge}" if badge else ""),
     f"Nova3D-hosted {label}; the exact price is checked before generation",
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
    "Connect a provider key above",
    "Provider-key models appear after their key and model access are verified",
    "ERROR", 999,
)


def access_mode(scene):
    """Translate the simple UI checkbox into the workflow billing contract."""
    return (constants.BILLING_PROVIDER_KEY
            if bool(getattr(scene, "nova3d_use_provider_key", False))
            else constants.BILLING_NOVA3D_CREDITS)


def available_model_options(context, billing_mode=None):
    scene = getattr(context, "scene", None)
    mode = billing_mode or access_mode(scene)
    if mode != constants.BILLING_PROVIDER_KEY:
        return constants.HOSTED_MODEL_OPTIONS
    try:
        from .preferences import get_prefs
        return provider_access.available_provider_options(get_prefs(context))
    except Exception:
        return ()


def _model_enum_items(_self, context):
    mode = access_mode(getattr(context, "scene", None))
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
    mode = access_mode(scene)
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


def _use_provider_key_changed(_scene, context):
    scene = getattr(context, "scene", None)
    if scene is None:
        return
    if scene.nova3d_use_provider_key:
        options = available_model_options(context, constants.BILLING_PROVIDER_KEY)
        desired = (options[0][0] if options else constants.PROVIDER_SETUP_OPTION_ID)
    else:
        desired = constants.DEFAULT_MODEL_OPTION_ID
    try:
        scene.nova3d_model = desired
    except Exception:
        pass
    if not scene.nova3d_use_provider_key:
        _schedule_credit_refresh()
    _tag_redraw(context)


def _model_changed(_scene, context):
    scene = getattr(context, "scene", None)
    if scene is not None and not getattr(scene, "nova3d_use_provider_key", False):
        # The previous model's quote must disappear synchronously. The refresh
        # operator may still be busy, and keeping the old value would make the
        # Generate label look like a static price for the newly selected model.
        wm = getattr(context, "window_manager", None)
        if wm is not None:
            wm.nova3d_required_credits = -1
            wm.nova3d_credit_estimate_model = ""
        _schedule_credit_refresh()
    _tag_redraw(context)


_credit_refresh_scheduled = False
_credit_refresh_retry_count = 0


def _schedule_credit_refresh():
    """Refresh balance + authoritative model cost after a hosted-model change.

    Enum update callbacks can run in contexts where invoking an operator inline
    is unsafe. A one-shot timer moves the call back onto Blender's main loop.
    """
    global _credit_refresh_scheduled, _credit_refresh_retry_count
    if _credit_refresh_scheduled:
        return
    _credit_refresh_scheduled = True
    _credit_refresh_retry_count = 0

    def refresh():
        global _credit_refresh_scheduled, _credit_refresh_retry_count
        # A prior balance/quote request can still be completing when the user
        # chooses another model. Wait for it rather than dropping this refresh.
        wm = getattr(bpy.context, "window_manager", None)
        if wm is not None and getattr(wm, "nova3d_credits_busy", False):
            _credit_refresh_retry_count += 1
            if _credit_refresh_retry_count < 200:  # ~20 seconds at 0.1s
                return 0.1
            _credit_refresh_scheduled = False
            _credit_refresh_retry_count = 0
            return None
        _credit_refresh_scheduled = False
        _credit_refresh_retry_count = 0
        try:
            bpy.ops.nova3d.refresh_credits("INVOKE_DEFAULT")
        except Exception:
            pass
        return None

    try:
        bpy.app.timers.register(refresh, first_interval=0.05)
    except Exception:
        _credit_refresh_scheduled = False


def _tag_redraw(context):
    screen = getattr(context, "screen", None)
    for area in getattr(screen, "areas", []) or []:
        if area.type == "VIEW_3D":
            area.tag_redraw()


def register_properties():
    bpy.utils.register_class(Nova3DReferenceImage)

    scene = bpy.types.Scene
    scene.nova3d_prompt = bpy.props.StringProperty(
        name="Prompt",
        description="Describe the 3D model to generate (max 40 words)",
        default="",
    )
    scene.nova3d_use_provider_key = bpy.props.BoolProperty(
        name="Use my own API key",
        description="Use a connected Anthropic or OpenAI key instead of Nova3D Credits",
        default=False,
        update=_use_provider_key_changed,
    )
    scene.nova3d_provider_setup = bpy.props.EnumProperty(
        name="Provider",
        description="Provider key to connect or manage",
        items=(
            (constants.PROVIDER_ANTHROPIC, "Anthropic", "Connect an Anthropic key"),
            (constants.PROVIDER_OPENAI, "OpenAI", "Connect an OpenAI key"),
        ),
        default=constants.PROVIDER_ANTHROPIC,
    )
    scene.nova3d_model = bpy.props.EnumProperty(
        name="Model",
        description="Which LLM writes the Blender program",
        items=_model_enum_items,
        # Dynamic EnumProperty callbacks require an integer default. Item 2 is
        # the hosted Claude Fable 5 recommendation.
        default=2,
        update=_model_changed,
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
    wm.nova3d_required_credits = bpy.props.IntProperty(default=-1)
    wm.nova3d_credit_estimate_model = bpy.props.StringProperty(default="")
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
    for attr in ("nova3d_prompt", "nova3d_model", "nova3d_use_provider_key",
                 "nova3d_provider_setup",
                 "nova3d_images", "nova3d_images_index"):
        if hasattr(scene, attr):
            delattr(scene, attr)

    wm = bpy.types.WindowManager
    for attr in ("nova3d_running", "nova3d_signing_in", "nova3d_status",
                 "nova3d_workflow_id", "nova3d_credits",
                 "nova3d_credits_busy", "nova3d_required_credits",
                 "nova3d_credit_estimate_model", "nova3d_last_dir", "nova3d_pending",
                 "nova3d_conversation_id", "nova3d_provider_test_busy",
                 "nova3d_provider_test_name",
                 "nova3d_service_down", "nova3d_update_available",
                 "nova3d_latest_version", "nova3d_release_url",
                 "nova3d_updates_busy"):
        if hasattr(wm, attr):
            delattr(wm, attr)

    bpy.utils.unregister_class(Nova3DReferenceImage)
