# SPDX-License-Identifier: MIT
"""Add / remove the user's own provider (BYOK) API keys from the N-panel.

One paste field serves all four providers: the provider is identified from the
key's prefix (`constants.detect_byok_provider`) and the key is written into that
provider's slot in add-on preferences. Pasting keys for different providers
therefore accumulates — each one unlocks its own models — while re-pasting for a
provider that already has a key simply replaces it.

The transient paste field lives on the WindowManager, so a key in flight is
never written into the .blend; only the preferences slot persists.
"""

import bpy

from .. import constants
from ..preferences import byok_key_prop_name, get_prefs


class NOVA3D_OT_add_api_key(bpy.types.Operator):
    bl_idname = "nova3d.add_api_key"
    bl_label = "Add Key"
    bl_description = ("Save the pasted provider API key. The provider is "
                      "detected automatically from the key")

    def execute(self, context):
        prefs = get_prefs(context)
        if prefs is None:
            self.report({"ERROR"}, "Add-on preferences are unavailable.")
            return {"CANCELLED"}

        wm = context.window_manager
        key = (wm.nova3d_key_input or "").strip()
        if not key:
            self.report({"ERROR"}, "Paste a provider API key first.")
            return {"CANCELLED"}

        provider = constants.detect_byok_provider(key)
        if not provider:
            self.report({"ERROR"}, constants.BYOK_KEY_FORMAT_HINT)
            return {"CANCELLED"}

        label = constants.byok_provider_label(provider)
        replaced = bool(getattr(prefs, byok_key_prop_name(provider), "").strip())
        setattr(prefs, byok_key_prop_name(provider), key)
        # Clear the paste field so the raw key is not left on screen.
        wm.nova3d_key_input = ""

        self.report({"INFO"}, f"{label} key {'replaced' if replaced else 'added'}. "
                              f"Its models are now available.")
        _tag_redraw(context)
        return {"FINISHED"}


class NOVA3D_OT_remove_api_key(bpy.types.Operator):
    bl_idname = "nova3d.remove_api_key"
    bl_label = "Remove Key"
    bl_description = "Forget this provider API key and hide its models"

    provider: bpy.props.StringProperty(
        name="Provider", default="", options={"HIDDEN"})

    def execute(self, context):
        prefs = get_prefs(context)
        if prefs is None or not self.provider:
            return {"CANCELLED"}
        setattr(prefs, byok_key_prop_name(self.provider), "")
        self.report({"INFO"},
                    f"{constants.byok_provider_label(self.provider)} key removed.")
        _tag_redraw(context)
        return {"FINISHED"}


def _tag_redraw(context):
    for area in getattr(context.screen, "areas", []) or []:
        if area.type == "VIEW_3D":
            area.tag_redraw()
