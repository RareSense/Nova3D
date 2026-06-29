# SPDX-License-Identifier: MIT
"""Scene + WindowManager properties for the add-on.

Scene properties hold user *input* (prompt, model, reference images) and are
saved with the .blend. WindowManager properties hold transient *runtime* state
(status line, busy flag, cached credit count) and are intentionally not saved.
"""

import bpy

from . import constants


class Nova3DReferenceImage(bpy.types.PropertyGroup):
    """One reference image path in the per-scene image list."""
    path: bpy.props.StringProperty(
        name="Path", subtype="FILE_PATH", description="Reference image file")


# Static EnumProperty items, built once. Using a module-level list (rather than a
# dynamic callback) avoids Blender's well-known crash where strings returned by an
# items callback are garbage-collected while still referenced by the UI.
_MODEL_ENUM_ITEMS = [
    (option_id,
     f"{label} — {credits} credits" + (f" ({badge})" if badge else ""),
     f"{label}: {credits} credits")
    for option_id, label, _tier, credits, badge in constants.MODEL_OPTIONS
]


def register_properties():
    bpy.utils.register_class(Nova3DReferenceImage)

    scene = bpy.types.Scene
    scene.nova3d_prompt = bpy.props.StringProperty(
        name="Prompt",
        description="Describe the 3D model to generate (max 40 words)",
        default="",
    )
    scene.nova3d_model = bpy.props.EnumProperty(
        name="Model",
        description="Which LLM writes the Blender program (priced in credits)",
        items=_MODEL_ENUM_ITEMS,
        default=constants.DEFAULT_MODEL_OPTION_ID,
    )
    scene.nova3d_images = bpy.props.CollectionProperty(type=Nova3DReferenceImage)
    scene.nova3d_images_index = bpy.props.IntProperty(name="Image", default=0)

    wm = bpy.types.WindowManager
    wm.nova3d_running = bpy.props.BoolProperty(default=False)
    wm.nova3d_signing_in = bpy.props.BoolProperty(default=False)
    wm.nova3d_status = bpy.props.StringProperty(default="")
    wm.nova3d_uv_status = bpy.props.StringProperty(default="")
    wm.nova3d_workflow_id = bpy.props.StringProperty(default="")
    wm.nova3d_credits = bpy.props.IntProperty(default=-1)  # -1 = unknown
    wm.nova3d_credits_busy = bpy.props.BoolProperty(default=False)
    wm.nova3d_last_dir = bpy.props.StringProperty(default="")
    wm.nova3d_pending = bpy.props.IntProperty(default=0)  # interrupted runs to resume


def unregister_properties():
    scene = bpy.types.Scene
    for attr in ("nova3d_prompt", "nova3d_model", "nova3d_images",
                 "nova3d_images_index"):
        if hasattr(scene, attr):
            delattr(scene, attr)

    wm = bpy.types.WindowManager
    for attr in ("nova3d_running", "nova3d_signing_in", "nova3d_status",
                 "nova3d_uv_status", "nova3d_workflow_id", "nova3d_credits",
                 "nova3d_credits_busy", "nova3d_last_dir", "nova3d_pending"):
        if hasattr(wm, attr):
            delattr(wm, attr)

    bpy.utils.unregister_class(Nova3DReferenceImage)
