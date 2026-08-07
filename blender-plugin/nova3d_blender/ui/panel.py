# SPDX-License-Identifier: MIT
"""The Nova3D N-panel (View3D > Sidebar > Nova3D).

Sections, top to bottom:
  * Account gate — if no API key, prompt the user to create one.
  * Nova3D Credits — current balance, refresh, and purchase link.
  * Optional OpenRouter BYOK selection and key field.
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

        # A new-version notice is independent of sign-in, so it draws first.
        _draw_update_banner(layout, wm)

        # ── Account gate ─────────────────────────────────────────────────────
        if prefs is None or not prefs.api_key.strip():
            box = layout.box()
            box.label(text="Connect your Nova3D account", icon="USER")
            if wm.nova3d_signing_in:
                box.label(text=wm.nova3d_status or "Signing in…", icon="SORTTIME")
                box.label(text="Finish in your browser (Esc to cancel).")
                return
            # Primary: one-click browser sign-in (no key to copy).
            big = box.row()
            big.scale_y = 1.4
            big.operator("nova3d.sign_in", icon="USER")
            # Fallback: paste a key (for headless / locked-down setups).
            box.separator()
            box.label(text="or use an API key:")
            row = box.row(align=True)
            row.operator("nova3d.enter_api_key", text="Enter Key", icon="GREASEPENCIL")
            row.operator("nova3d.open_api_key", text="Create Key", icon="URL")
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

        # ── Service reachability ─────────────────────────────────────────────
        if wm.nova3d_service_down:
            down = layout.box()
            down.alert = True
            down.label(text="Nova3D is unreachable right now.", icon="ERROR")
            down.label(text="Check your connection, then retry.")
            down.operator("nova3d.refresh_credits", text="Retry", icon="FILE_REFRESH")

        # ── Resume interrupted generations ───────────────────────────────────
        pending = wm.nova3d_pending
        if pending > 0 and not running:
            rbox = layout.box()
            rbox.label(
                text=f"{pending} generation(s) waiting to finish",
                icon="RECOVER_LAST")
            rbox.operator("nova3d.resume",
                          text=f"Resume {pending} pending", icon="PLAY")

        # ── Nova3D Credits / OpenRouter BYOK ─────────────────────────────────
        box = layout.box()
        row = box.row(align=True)
        credits = wm.nova3d_credits
        credits_text = ("Nova3D Credits: —" if credits < 0
                        else f"Nova3D Credits: {credits}")
        row.label(text=credits_text, icon="FUND")
        sub = row.row(align=True)
        sub.enabled = not wm.nova3d_credits_busy
        sub.operator("nova3d.refresh_credits", text="", icon="FILE_REFRESH")
        box.operator("nova3d.buy_credits", icon="URL")

        byok = layout.box()
        byok.enabled = not running
        byok.label(text="Or use your OpenRouter key", icon="KEY_HLT")
        byok.prop(scene, "nova3d_use_openrouter", text="Use OpenRouter instead")
        if scene.nova3d_use_openrouter:
            byok.prop(prefs, "openrouter_api_key", text="Key")
            byok.operator("nova3d.open_openrouter_keys", icon="URL",
                          text="Create an OpenRouter key")
            if prefs.openrouter_api_key.strip():
                byok.label(text="OpenRouter bills your account directly.",
                           icon="CHECKMARK")
                byok.label(text="No Nova3D Credits are used.")
            else:
                warning = byok.row()
                warning.alert = True
                warning.label(text="Enter an OpenRouter key to use this option.",
                              icon="ERROR")

        # ── Inputs ───────────────────────────────────────────────────────────
        col = layout.column()
        col.enabled = not running
        col.label(text="Prompt")
        col.prop(scene, "nova3d_prompt", text="")
        _draw_word_counter(col, scene.nova3d_prompt)
        col.prop(scene, "nova3d_model", text="Model")
        selected = constants.model_option_by_id(scene.nova3d_model)
        if scene.nova3d_use_openrouter:
            col.label(text="Cost: your OpenRouter usage; 0 Nova3D Credits")
        else:
            col.label(text=f"Cost: {selected[3]} Nova3D Credits")

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
            if wm.nova3d_workflow_id:
                row = sbox.row(align=True)
                row.label(text=f"Workflow: {wm.nova3d_workflow_id}", icon="FILE_TEXT")
                row.operator("nova3d.copy_workflow_id", text="", icon="COPYDOWN")

        # ── Last generation ──────────────────────────────────────────────────
        if wm.nova3d_last_dir:
            box = layout.box()
            box.label(text="Saved to:", icon="FILE_FOLDER")
            # Folder name (timestamp_slug) is the most useful at-a-glance; the
            # full path is shown below it and via the open button.
            box.label(text=bpy.path.basename(wm.nova3d_last_dir.rstrip("/")))
            box.label(text=wm.nova3d_last_dir)
            box.operator("nova3d.open_output_folder", text="Open Folder",
                         icon="FILEBROWSER")

        # ── Account footer (how you're connected + sign out) ─────────────────
        layout.separator()
        foot = layout.row(align=True)
        connected = "Signed in" if prefs.key_source == "sign_in" else "API key"
        foot.label(text=connected, icon="CHECKMARK")
        foot.operator("nova3d.sign_out", text="Sign out", icon="PANEL_CLOSE")


def _draw_update_banner(layout, wm):
    """A subtle 'newer version available' notice, shown only when one exists."""
    if not wm.nova3d_update_available:
        return
    box = layout.box()
    box.label(text=f"Update available: v{wm.nova3d_latest_version}", icon="IMPORT")
    url = wm.nova3d_release_url or constants.RELEASES_PAGE_URL
    box.operator("wm.url_open", text="Download update", icon="URL").url = url


def _draw_word_counter(layout, prompt):
    words = len((prompt or "").split())
    row = layout.row()
    row.alignment = "RIGHT"
    over = words > constants.MAX_PROMPT_WORDS
    row.alert = over
    row.label(text=f"{words}/{constants.MAX_PROMPT_WORDS} words")
