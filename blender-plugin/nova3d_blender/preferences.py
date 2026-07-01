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
        description="Your Nova3D credential (an n3d_ token). Set by signing in, "
                    "or paste a key created on the web.",
        default="",
        subtype="PASSWORD",
    )
    # How the credential was obtained ("sign_in" | "manual" | ""), and its expiry
    # if known. Hidden — used for messaging and sign-out, not user-edited.
    key_source: bpy.props.StringProperty(default="", options={"HIDDEN"})
    key_expires_at: bpy.props.StringProperty(default="", options={"HIDDEN"})
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
    clean_viewport: bpy.props.BoolProperty(
        name="Clean Viewport on Import",
        description="After importing, hide other objects and switch to Material "
                    "Preview so the new generation shows clearly with its colours. "
                    "Reversible — unhide with Alt+H. Turn off to keep your scene as-is",
        default=True,
    )

    def draw(self, context):
        layout = self.layout

        box = layout.box()
        box.label(text="Account", icon="USER")
        if self.api_key.strip():
            connected = "Signed in with Google" if self.key_source == "sign_in" \
                else "Connected with an API key"
            box.label(text=connected, icon="CHECKMARK")
            box.operator("nova3d.sign_out", icon="PANEL_CLOSE")
        else:
            row = box.row()
            row.scale_y = 1.3
            row.operator("nova3d.sign_in", icon="USER")
            box.label(text="— or —")
        # Manual key field is always available as a fallback / override.
        box.prop(self, "api_key")
        box.operator("nova3d.open_api_key", icon="URL", text="Create a key on the web")

        box = layout.box()
        box.label(text="Storage", icon="FILE_FOLDER")
        box.prop(self, "output_dir")
        box.prop(self, "clean_viewport")

        box = layout.box()
        box.label(text="Endpoints (advanced / self-hosting)", icon="WORLD")
        box.prop(self, "api_base_url")
        box.prop(self, "web_base_url")

        wm = context.window_manager
        box = layout.box()
        box.label(text=f"Version {constants.ADDON_VERSION_STR}", icon="BLENDER")
        if wm.nova3d_update_available:
            row = box.row()
            row.alert = True
            row.label(text=f"Update available: v{wm.nova3d_latest_version}",
                      icon="IMPORT")
            box.operator("wm.url_open", text="Download update", icon="URL").url = (
                wm.nova3d_release_url or constants.RELEASES_PAGE_URL)
        box.operator("nova3d.check_updates", icon="FILE_REFRESH")


def get_prefs(context):
    """Return this add-on's preferences, or None if unavailable."""
    addon = context.preferences.addons.get(ADDON_ID)
    return addon.preferences if addon else None


def has_credential(prefs):
    return bool(prefs and prefs.api_key.strip())


def set_credential(prefs, token, *, source, expires_at=None):
    """Store a credential and how it was obtained (persists in user prefs)."""
    prefs.api_key = token
    prefs.key_source = source
    prefs.key_expires_at = expires_at or ""


def clear_credential(prefs):
    """Sign out / forget the stored credential."""
    prefs.api_key = ""
    prefs.key_source = ""
    prefs.key_expires_at = ""
