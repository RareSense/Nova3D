# SPDX-License-Identifier: MIT
"""The Nova3D N-panel (View3D > Sidebar > Nova3D).

Sections, top to bottom:
  * Account gate — if no API key, prompt the user to create one.
  * Credits — current balance, refresh, and Buy Credits.
  * Prompt + model + reference images.
  * Generate / Cancel + live status.
  * Last generation — open the project folder.
"""

import bpy

from .. import constants
from ..preferences import get_prefs, online_access_ok


class NOVA3D_UL_images(bpy.types.UIList):
    """Compact list of attached reference images."""

    def draw_item(self, context, layout, data, item, icon, active_data,
                  active_propname, index):
        row = layout.row(align=True)
        row.label(text=bpy.path.basename(item.path) or "(image)", icon="IMAGE_DATA")
        op = row.operator("nova3d.remove_image", text="", icon="X", emboss=False)
        op.index = index


class NOVA3D_PT_main(bpy.types.Panel):
    bl_label = "Nova3D"
    bl_idname = "NOVA3D_PT_main"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Nova3D"

    def draw(self, context):
        layout = self.layout
        wm = context.window_manager
        scene = context.scene
        prefs = get_prefs(context)

        # ── Account gate ─────────────────────────────────────────────────────
        if prefs is None or not prefs.api_key.strip():
            box = layout.box()
            box.label(text="Connect your Nova3D account", icon="USER")
            box.label(text="Create an account and API key, then")
            box.label(text="paste the key in add-on preferences.")
            box.operator("nova3d.open_api_key", icon="URL")
            box.operator("screen.userpref_show", text="Open Preferences",
                         icon="PREFERENCES")
            return

        running = wm.nova3d_running

        # ── Online-access gate (Blender 4.2+/5.x) ────────────────────────────
        if not online_access_ok():
            warn = layout.box()
            warn.alert = True
            warn.label(text="Online access is disabled.", icon="ERROR")
            warn.label(text="Enable it in Preferences > System.")
            warn.operator("screen.userpref_show", text="Open Preferences",
                          icon="PREFERENCES")

        # ── Credits ──────────────────────────────────────────────────────────
        box = layout.box()
        row = box.row(align=True)
        credits = wm.nova3d_credits
        credits_text = "Credits: —" if credits < 0 else f"Credits: {credits}"
        row.label(text=credits_text, icon="FUND")
        sub = row.row(align=True)
        sub.enabled = not wm.nova3d_credits_busy
        sub.operator("nova3d.refresh_credits", text="", icon="FILE_REFRESH")
        box.operator("nova3d.buy_credits", icon="URL")

        # ── Inputs ───────────────────────────────────────────────────────────
        col = layout.column()
        col.enabled = not running
        col.label(text="Prompt")
        col.prop(scene, "nova3d_prompt", text="")
        _draw_word_counter(col, scene.nova3d_prompt)
        col.prop(scene, "nova3d_model", text="Model")

        # Reference images (optional, up to 3).
        img_box = layout.box()
        img_box.enabled = not running
        header = img_box.row(align=True)
        header.label(text=f"Reference Images ({len(scene.nova3d_images)}/"
                          f"{constants.MAX_REFERENCE_IMAGES})", icon="IMAGE_DATA")
        if scene.nova3d_images:
            header.operator("nova3d.clear_images", text="", icon="TRASH")
        if scene.nova3d_images:
            img_box.template_list("NOVA3D_UL_images", "", scene, "nova3d_images",
                                  scene, "nova3d_images_index", rows=2)
        add_row = img_box.row()
        add_row.enabled = len(scene.nova3d_images) < constants.MAX_REFERENCE_IMAGES
        add_row.operator("nova3d.add_images", icon="ADD")

        # ── Generate / Cancel ────────────────────────────────────────────────
        layout.separator()
        if running:
            layout.operator("nova3d.cancel", text="Cancel", icon="CANCEL")
        else:
            row = layout.row()
            row.scale_y = 1.5
            row.operator("nova3d.generate", text="Generate", icon="MESH_MONKEY")

        # ── Status ───────────────────────────────────────────────────────────
        if wm.nova3d_status:
            sbox = layout.box()
            icon = "SORTTIME" if running else "CHECKMARK"
            sbox.label(text=wm.nova3d_status, icon=icon)
            if wm.nova3d_uv_status:
                sbox.label(text=wm.nova3d_uv_status, icon="UV")

        # ── Last generation ──────────────────────────────────────────────────
        if wm.nova3d_last_dir:
            layout.operator("nova3d.open_output_folder", icon="FILE_FOLDER")


def _draw_word_counter(layout, prompt):
    words = len((prompt or "").split())
    row = layout.row()
    row.alignment = "RIGHT"
    over = words > constants.MAX_PROMPT_WORDS
    row.alert = over
    row.label(text=f"{words}/{constants.MAX_PROMPT_WORDS} words")
