# SPDX-License-Identifier: MIT
"""The Nova3D N-panel (View3D > Sidebar > Nova3D).

Sections, top to bottom:
  * Account gate — if no API key, prompt the user to create one.
  * One generation-access card for Nova3D Credits or verified provider keys.
  * Prompt + model + reference images.
  * Generate / Cancel + live status.
  * Last generation — open the project folder.
"""

import bpy

from .. import constants
from .. import properties
from ..preferences import get_prefs, online_access_ok
from ..services import provider_access


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
            rbox.label(text="The backend keeps running if Blender disconnects.")
            row = rbox.row(align=True)
            row.operator("nova3d.resume",
                         text=f"Resume {pending}", icon="PLAY")
            row.operator("nova3d.open_web_run", text="Open App", icon="URL")

        # ── Generation access + model ────────────────────────────────────────
        access = layout.box()
        access.label(text="Nova3D Credits", icon="FUND")
        _draw_credit_access(access, wm)
        access.separator()
        toggle = access.row()
        toggle.enabled = not running
        toggle.prop(scene, "nova3d_use_provider_key")
        if scene.nova3d_use_provider_key:
            _draw_provider_access(access, prefs, wm, scene, running)
        available = properties.available_model_options(context)
        exact_selected = next(
            (option for option in available if option[0] == scene.nova3d_model),
            None,
        )
        model_row = access.row()
        model_row.enabled = bool(not running and exact_selected is not None)
        model_row.prop(scene, "nova3d_model", text="Model")
        ready, access_message = _generation_access_state(scene, wm, exact_selected)
        if scene.nova3d_use_provider_key and exact_selected:
            provider = constants.provider_for_option(exact_selected)
            access.label(text=f"Usage billed by {provider_access.provider_label(provider)}.",
                         icon="CHECKMARK")
        elif not scene.nova3d_use_provider_key and exact_selected:
            required = wm.nova3d_required_credits
            if required >= 0 and wm.nova3d_credit_estimate_model == exact_selected[0]:
                access.label(text=f"This generation needs {required} credits.")

        # ── Inputs ───────────────────────────────────────────────────────────
        col = layout.column()
        col.enabled = not running
        col.label(text="Prompt")
        col.prop(scene, "nova3d_prompt", text="")
        _draw_word_counter(col, scene.nova3d_prompt)

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
            layout.operator("nova3d.cancel", text="Stop waiting in Blender",
                            icon="CANCEL")
            layout.label(text="The backend run continues and stays in the app.")
        else:
            row = layout.row()
            row.scale_y = 1.5
            row.enabled = ready and online_access_ok() and not wm.nova3d_service_down
            button_text = "Generate"
            if ready and not scene.nova3d_use_provider_key:
                button_text = f"Generate · {wm.nova3d_required_credits} credits"
            row.operator("nova3d.generate", text=button_text, icon="MESH_MONKEY")
            if not ready and access_message:
                action = layout.box()
                action.alert = True
                _draw_wrapped(action, access_message, icon="INFO")
                buttons = action.row(align=True)
                if scene.nova3d_use_provider_key:
                    buttons.operator("nova3d.use_credits", text="Use Nova3D Credits",
                                     icon="FUND")
                else:
                    buttons.operator("nova3d.buy_credits", text="Buy credits", icon="URL")
                    buttons.operator("nova3d.use_provider_key", text="Use my API key",
                                     icon="KEY_HLT")

        # ── Status ───────────────────────────────────────────────────────────
        if wm.nova3d_status:
            sbox = layout.box()
            status_lower = wm.nova3d_status.lower()
            is_error = any(word in status_lower for word in (
                "failed", "rejected", "lost connection", "could not", "not enabled"))
            icon = "SORTTIME" if running else ("ERROR" if is_error else "CHECKMARK")
            sbox.label(text=wm.nova3d_status, icon=icon)
            if wm.nova3d_workflow_id:
                row = sbox.row(align=True)
                row.label(text=f"Workflow: {wm.nova3d_workflow_id}", icon="FILE_TEXT")
                row.operator("nova3d.copy_workflow_id", text="", icon="COPYDOWN")
            if wm.nova3d_conversation_id or wm.nova3d_workflow_id:
                sbox.operator("nova3d.open_web_run", text="Open run in Nova3D App",
                              icon="URL")

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
    """Offer a verified in-Blender update when a newer release exists."""
    if not wm.nova3d_update_available:
        return
    box = layout.box()
    box.label(text=f"Update available: v{wm.nova3d_latest_version}", icon="IMPORT")
    row = box.row()
    row.enabled = not wm.nova3d_updates_busy
    row.operator("nova3d.install_update", text="Update Nova3D", icon="IMPORT")


def _draw_credit_access(box, wm):
    row = box.row(align=True)
    credits = wm.nova3d_credits
    credits_text = ("Checking balance…" if credits < 0 else f"Balance: {credits} credits")
    row.label(text=credits_text, icon="FUND")
    refresh = row.row(align=True)
    refresh.enabled = not wm.nova3d_credits_busy
    refresh.operator("nova3d.refresh_credits", text="", icon="FILE_REFRESH")
    row.operator("nova3d.buy_credits", text="Buy", icon="URL")


def _draw_provider_access(box, prefs, wm, scene, running):
    box.label(text="Your provider bills usage. Keep enough API balance to finish.")
    provider_row = box.row()
    provider_row.enabled = not running
    provider_row.prop(scene, "nova3d_provider_setup", expand=True)
    _draw_provider_card(box, prefs, wm, scene.nova3d_provider_setup, running)
    if not provider_access.available_provider_options(prefs):
        box.label(text="Connect an Anthropic or OpenAI key to continue.", icon="INFO")


def _draw_provider_card(parent, prefs, wm, provider, running):
    label = provider_access.provider_label(provider)
    key_attr = ("anthropic_api_key" if provider == constants.PROVIDER_ANTHROPIC
                else "openai_api_key")
    message_attr = ("anthropic_validation_message"
                    if provider == constants.PROVIDER_ANTHROPIC
                    else "openai_validation_message")
    key = provider_access.provider_key(prefs, provider)
    current = provider_access.validation_is_current(prefs, provider)
    busy = wm.nova3d_provider_test_busy and wm.nova3d_provider_test_name == provider

    card = parent.box()
    card.enabled = not running
    header = card.row(align=True)
    header.label(text=label, icon="CHECKMARK" if current else "KEY_HLT")
    if key:
        clear = header.operator("nova3d.clear_provider_key", text="", icon="X")
        clear.provider = provider
    card.prop(prefs, key_attr, text="API key")

    links = card.row(align=True)
    create = links.operator("nova3d.open_provider_page", text="Get key", icon="URL")
    create.destination = "anthropic_keys" if provider == constants.PROVIDER_ANTHROPIC else "openai_keys"
    billing = links.operator(
        "nova3d.open_provider_page", text="Billing", icon="FUND")
    billing.destination = ("anthropic_billing" if provider == constants.PROVIDER_ANTHROPIC
                           else "openai_billing")
    if provider == constants.PROVIDER_OPENAI:
        models = card.operator("nova3d.open_provider_page",
                               text="Enable GPT-5.6 Sol & GPT-5.5", icon="SETTINGS")
        models.destination = "openai_models"
    test = card.row()
    test.enabled = bool(key and not wm.nova3d_provider_test_busy)
    op = test.operator("nova3d.test_provider_key",
                       text=(f"Connecting {label}…" if busy else
                             ("Reconnect" if current else "Connect")),
                       icon="FILE_REFRESH" if busy else "CHECKMARK")
    op.provider = provider

    message = getattr(prefs, message_attr, "")
    if message:
        _draw_wrapped(card, message, icon="CHECKMARK" if current else "ERROR")


def _generation_access_state(scene, wm, selected):
    """Return (ready, user-facing reason) without relying on enum fallbacks."""
    if selected is None:
        if getattr(scene, "nova3d_use_provider_key", False):
            return False, "Connect an Anthropic or OpenAI key, or use Nova3D Credits."
        return False, "Choose a model."
    if getattr(scene, "nova3d_use_provider_key", False):
        return True, ""
    if wm.nova3d_credits_busy:
        return False, "Checking your Nova3D Credits…"
    if wm.nova3d_credit_estimate_model != selected[0] or wm.nova3d_required_credits < 0:
        return False, "Check your Nova3D credit balance to continue."
    if wm.nova3d_credits < 0:
        return False, "Could not confirm your Nova3D credit balance. Refresh and try again."
    required = wm.nova3d_required_credits
    available = wm.nova3d_credits
    if available < required:
        return False, (f"This model needs {required} credits; you have {available}. "
                       "Buy credits or use your own API key.")
    return True, ""


def _draw_wrapped(layout, message, *, icon="NONE", width=52):
    words = str(message or "").split()
    lines = []
    current = []
    for word in words:
        if current and len(" ".join(current + [word])) > width:
            lines.append(" ".join(current))
            current = [word]
        else:
            current.append(word)
    if current:
        lines.append(" ".join(current))
    for index, line in enumerate(lines):
        layout.label(text=line, icon=icon if index == 0 else "NONE")


def _draw_word_counter(layout, prompt):
    words = len((prompt or "").split())
    row = layout.row()
    row.alignment = "RIGHT"
    over = words > constants.MAX_PROMPT_WORDS
    row.alert = over
    row.label(text=f"{words}/{constants.MAX_PROMPT_WORDS} words")
