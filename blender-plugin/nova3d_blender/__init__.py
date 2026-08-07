# SPDX-License-Identifier: MIT
"""Nova3D — Code-native 3D generation, natively inside Blender.

This add-on drives the hosted Nova3D / GraphFlow backend (the same service the
web app uses) to generate part-structured 3D assets from a text prompt and
optional reference images. Generations use Nova3D Credits or OpenRouter, are
written to a per-generation project folder on disk, imported into the scene,
and synced to the user's web chat history.

It requires ZERO backend changes: every call uses the public GraphFlow API with
the user's Nova3D API key. See ``README.md`` for the full data flow.

Package layout
--------------
    constants.py        endpoints, model catalogue, limits, labels
    preferences.py      API key, base URLs, output folder
    properties.py       scene inputs + transient runtime state
    api/                stdlib HTTP + typed client + result parsing (no bpy)
    services/           generation worker, history, project store, UV, images
    scene_io/           GLB import + collections + text datablock (main thread)
    operators/          account, image management, the modal Generate operator
    ui/                 the N-panel
"""

bl_info = {
    "name": "Nova3D — Code-native 3D Generation",
    "author": "RareSense (Nova3D)",
    "version": (1, 1, 0),
    "blender": (3, 6, 0),
    "location": "View3D > Sidebar (N) > Nova3D",
    "description": "Generate part-structured 3D assets from text prompts using "
                   "the hosted Nova3D backend with Nova3D Credits or OpenRouter.",
    "category": "3D View",
    "doc_url": "https://nova3d.xyz",
    "tracker_url": "https://github.com/RareSense/Nova3D/issues",
}

import bpy

from . import preferences, properties
from . import operators, ui


def _deferred_startup():
    """Run shortly after enable: load the Nova3D Credits balance and resume any
    generations that were interrupted (so closing Blender / a dropped network
    never loses a running, paid generation). One-shot — returns None.

    Deferred (not run inline at register) so a window/context exists for the
    modal operators it launches. Fully guarded: a startup hiccup never breaks
    add-on registration, and the Resume button remains as a manual fallback.
    """
    try:
        context = bpy.context
        prefs = preferences.get_prefs(context)
        operators.generate.update_pending_count(context)
        # Update check is independent of sign-in — run it first (once per session)
        # so even signed-out users learn a newer build exists.
        if preferences.online_access_ok():
            try:
                bpy.ops.nova3d.check_updates("INVOKE_DEFAULT")
            except Exception:
                pass
        if not (prefs and prefs.api_key.strip() and preferences.online_access_ok()):
            return None
        wm = context.window_manager
        if getattr(wm, "nova3d_credits", -1) < 0 and not getattr(wm, "nova3d_credits_busy", False):
            try:
                bpy.ops.nova3d.refresh_credits("INVOKE_DEFAULT")
            except Exception:
                pass
        if getattr(wm, "nova3d_pending", 0) > 0 and not operators.generate.is_generating():
            try:
                bpy.ops.nova3d.resume("INVOKE_DEFAULT")
            except Exception:
                pass
    except Exception:
        pass
    return None  # one-shot timer


def register():
    bpy.utils.register_class(preferences.Nova3DPreferences)
    properties.register_properties()
    for cls in operators.classes:
        bpy.utils.register_class(cls)
    for cls in ui.classes:
        bpy.utils.register_class(cls)
    try:
        bpy.app.timers.register(_deferred_startup, first_interval=1.5)
    except Exception:
        pass


def unregister():
    try:
        if bpy.app.timers.is_registered(_deferred_startup):
            bpy.app.timers.unregister(_deferred_startup)
    except Exception:
        pass
    for cls in reversed(ui.classes):
        bpy.utils.unregister_class(cls)
    for cls in reversed(operators.classes):
        bpy.utils.unregister_class(cls)
    properties.unregister_properties()
    bpy.utils.unregister_class(preferences.Nova3DPreferences)


if __name__ == "__main__":
    register()
