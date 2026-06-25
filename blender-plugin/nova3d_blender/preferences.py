# SPDX-License-Identifier: MIT
"""Add-on preferences: API key, base URLs, and the output folder.

The API key is the user's Nova3D key (``n3d_...``) created on the web at
``<web>/api-key``. It is stored in Blender's user preferences (not in the
.blend), so it never travels inside a shared scene file. We never log it and
never send it anywhere except as the ``Authorization`` header to the configured
API base.
"""

import bpy

from . import constants

# The add-on's module name, which `AddonPreferences.bl_idname` must equal so
# Blender can resolve the preferences. Because this module lives directly inside
# the add-on package, its `__package__` IS the add-on's top-level module name.
# This resolves correctly under BOTH install paths:
#   * legacy add-on:  "nova3d_blender"
#   * extension (4.2+/5.x):  "bl_ext.<repo>.nova3d_blender"
# (Using `__package__.partition('.')[0]` would wrongly yield "bl_ext" as an
# extension and the preferences/API key would never be found.)
ADDON_ID = __package__


def online_access_ok():
    """True when Blender permits network access (or predates the toggle).

    Blender 4.2+ added `bpy.app.online_access`; extensions must respect it.
    Older Blender has no such gate, so we treat the attribute's absence as
    "allowed".
    """
    return bool(getattr(bpy.app, "online_access", True))


class Nova3DPreferences(bpy.types.AddonPreferences):
    bl_idname = ADDON_ID

    api_key: bpy.props.StringProperty(
        name="API Key",
        description="Your Nova3D API key (starts with n3d_). Create one on the web.",
        default="",
        subtype="PASSWORD",
    )
    api_base_url: bpy.props.StringProperty(
        name="API Base URL",
        description="Hosted Nova3D API base. Change only for self-hosting.",
        default=constants.DEFAULT_API_BASE_URL,
    )
    web_base_url: bpy.props.StringProperty(
        name="Web Base URL",
        description="Hosted Nova3D website (for the API-key and credits pages).",
        default=constants.DEFAULT_WEB_BASE_URL,
    )
    output_dir: bpy.props.StringProperty(
        name="Output Folder",
        description="Where per-generation project folders are written",
        default="~/Nova3D",
        subtype="DIR_PATH",
    )

    def draw(self, context):
        layout = self.layout

        box = layout.box()
        box.label(text="Account", icon="USER")
        box.prop(self, "api_key")
        row = box.row()
        row.operator("nova3d.open_api_key", icon="URL",
                     text="Get / Create API Key")
        if not self.api_key.strip():
            box.label(text="No API key set — create one, then paste it above.",
                      icon="INFO")

        box = layout.box()
        box.label(text="Storage", icon="FILE_FOLDER")
        box.prop(self, "output_dir")

        box = layout.box()
        box.label(text="Endpoints (advanced / self-hosting)", icon="WORLD")
        box.prop(self, "api_base_url")
        box.prop(self, "web_base_url")


def get_prefs(context):
    """Return this add-on's preferences, or None if unavailable."""
    addon = context.preferences.addons.get(ADDON_ID)
    return addon.preferences if addon else None
