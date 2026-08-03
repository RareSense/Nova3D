# SPDX-License-Identifier: MIT
"""The Nova3D N-panel (View3D > Sidebar > Nova3D).

Sections, top to bottom:
  * Account gate — if no API key, prompt the user to create one.
  * Credits — current balance, refresh, and Buy Credits.
  * Prompt + model + reference images.
  * Generate + live status.
  * Last generation — open the project folder.
"""

import textwrap
import time

import bpy

from .. import constants
from ..preferences import byok_key_for, get_prefs, online_access_ok


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

        # ── 1. Your own API key ──────────────────────────────────────────────
        _draw_byok_section(layout, wm, scene, prefs, running)

        # ── or ───────────────────────────────────────────────────────────────
        sep = layout.row()
        sep.alignment = "CENTER"
        sep.label(text="— or —")

        # ── 2. Nova3D credits ────────────────────────────────────────────────
        _draw_credits_section(layout, wm, scene, running)

        # ── Prompt ───────────────────────────────────────────────────────────
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

        # ── Generate ─────────────────────────────────────────────────────────
        # No Cancel button: the backend has no cancel endpoint, so stopping here
        # would never stop the run — it would only hide a generation you have
        # already paid for. The run is left to finish and its result collected,
        # whatever comes back.
        layout.separator()
        row = layout.row()
        row.scale_y = 1.5
        row.enabled = not running
        row.operator("nova3d.generate", text="Generate", icon="MESH_MONKEY")

        # ── Status ───────────────────────────────────────────────────────────
        if wm.nova3d_status:
            sbox = layout.box()
            if running:
                _draw_spinner(sbox, "Generating…")
                # The per-stage line the worker reports, e.g. "Writing the
                # Blender scene…" — more useful than any percentage would be.
                sbox.label(text=wm.nova3d_status, icon="BLANK1")
                sbox.label(text=constants.LONG_RUN_NOTICE, icon="INFO")
            else:
                # Style by how the run actually ended. Previously this was always
                # a green tick, so a failure read as a success.
                outcome = wm.nova3d_outcome
                if outcome == "error":
                    sbox.alert = True
                    icon = "ERROR"
                elif outcome == "warn":
                    icon = "ERROR"
                else:
                    icon = "CHECKMARK"
                _draw_wrapped(sbox, wm.nova3d_status, icon=icon,
                              width_px=getattr(context.region, "width", 0))

        # ── Last generation ──────────────────────────────────────────────────
        # Just the button. The workflow id and the output path are still tracked
        # on the WindowManager (and the path is in the folder the button opens);
        # they are simply not worth the panel space.
        if wm.nova3d_last_dir:
            layout.operator("nova3d.open_output_folder", text="Open Folder",
                            icon="FILEBROWSER")

        # ── Account footer (how you're connected + sign out) ─────────────────
        layout.separator()
        foot = layout.row(align=True)
        connected = "Signed in" if prefs.key_source == "sign_in" else "API key"
        foot.label(text=connected, icon="CHECKMARK")
        foot.operator("nova3d.sign_out", text="Sign out", icon="PANEL_CLOSE")


def _draw_wrapped(layout, text, *, icon="NONE", width_px=0):
    """Draw *text* across as many label rows as it needs.

    Blender labels never wrap — they elide the middle, which turned backend
    errors into unreadable strings like "upstream result failed o..._attempts=3
    exhausted". Splitting the text ourselves is the only way to show all of it.
    The character budget is estimated from the region width (~7px per character
    at default UI scale), minus room for the icon and the box padding.
    """
    budget = max(24, int((width_px - 55) / 7)) if width_px else 38
    lines = textwrap.wrap(text, width=budget) or [text]
    col = layout.column(align=True)
    for index, line in enumerate(lines):
        col.label(text=line, icon=icon if index == 0 else "BLANK1")


def _draw_update_banner(layout, wm):
    """A subtle 'newer version available' notice, shown only when one exists."""
    if not wm.nova3d_update_available:
        return
    box = layout.box()
    box.label(text=f"Update available: v{wm.nova3d_latest_version}", icon="IMPORT")
    url = wm.nova3d_release_url or constants.RELEASES_PAGE_URL
    box.operator("wm.url_open", text="Download update", icon="URL").url = url


# Whether this build exposes `UILayout.progress()` (Blender 4.2+). Probed once
# on first draw and remembered, so a build without it falls back permanently to
# the text spinner instead of raising on every redraw.
_HAS_PROGRESS_WIDGET = None


def _spinner_phase():
    """Current 0.0–1.0 position in the rotation, derived purely from the clock.

    No stored frame counter is needed: the panel is redrawn on every modal timer
    tick while a generation runs, and each redraw simply reads the clock.
    """
    period = constants.SPINNER_PERIOD_SECONDS
    return (time.monotonic() % period) / period


def _draw_spinner(layout, text):
    """Indeterminate 'still working' indicator.

    Prefers Blender's native ring widget, whose factor is cycled rather than
    filled — deliberately indeterminate, because the backend reports the current
    node but never a percentage (see constants.SPINNER_FRAMES).
    """
    global _HAS_PROGRESS_WIDGET
    phase = _spinner_phase()

    if _HAS_PROGRESS_WIDGET is not False:
        try:
            layout.progress(factor=phase, text=text, type="RING")
            _HAS_PROGRESS_WIDGET = True
            return
        except (AttributeError, TypeError):
            # Older Blender, or a fork without the widget — use text frames.
            _HAS_PROGRESS_WIDGET = False

    layout.label(text=f"{constants.spinner_frame(phase)}  {text}")


def _draw_byok_section(layout, wm, scene, prefs, running):
    """Section 1 — run on your own provider key.

    One paste field serves all four providers (the provider is detected from the
    key prefix). Saved keys are listed compactly with a remove button, and the
    model dropdown below shows only the models those keys unlock.
    """
    active = scene.nova3d_billing == "byok"
    box = layout.box()

    header = box.row(align=True)
    header.label(text="Use Your Own API Key",
                 icon="CHECKMARK" if active else "KEYINGSET")
    tail = header.row()
    tail.alignment = "RIGHT"
    tail.label(text="0 credits")

    saved = [(pid, label) for pid, label, _prefix in constants.BYOK_PROVIDERS
             if byok_key_for(prefs, pid)]

    # Paste field + Add, disabled mid-generation like every other input.
    entry = box.row(align=True)
    entry.enabled = not running
    entry.prop(wm, "nova3d_key_input", text="")
    entry.operator("nova3d.add_api_key", text="Add", icon="ADD")

    if not saved:
        box.label(text="Paste a Gemini, Anthropic, OpenAI or OpenRouter key.")
        return

    for provider_id, label in saved:
        row = box.row(align=True)
        row.label(text=label, icon="CHECKMARK")
        remove = row.row()
        remove.enabled = not running
        remove.operator("nova3d.remove_api_key", text="", icon="X",
                        emboss=False).provider = provider_id

    model = box.column()
    model.enabled = not running
    model.active = active          # dimmed until this section is the chosen one
    model.prop(scene, "nova3d_byok_model", text="")

    # Spell out the balance the selected model expects. There is no credit hold
    # on a BYOK run, so a key that runs dry mid-generation loses whatever it had
    # already spent — this is the only warning the user gets.
    selected = constants.model_option_by_id(scene.nova3d_byok_model)
    if constants.is_byok_option(selected):
        minimum = constants.byok_min_balance_usd(selected)
        provider_label = constants.byok_provider_label(selected[5])
        note = model.row()
        note.label(text=f"Keep at least ${minimum} on your {provider_label} account.",
                   icon="INFO")


def _draw_credits_section(layout, wm, scene, running):
    """Section 2 — run on Nova3D credits (the original paid flow)."""
    active = scene.nova3d_billing == "credits"
    box = layout.box()

    header = box.row(align=True)
    credits = wm.nova3d_credits
    header.label(text="Credits: —" if credits < 0 else f"Credits: {credits}",
                 icon="CHECKMARK" if active else "FUND")
    refresh = header.row(align=True)
    refresh.alignment = "RIGHT"
    refresh.enabled = not wm.nova3d_credits_busy
    refresh.operator("nova3d.refresh_credits", text="", icon="FILE_REFRESH")

    model = box.column()
    model.enabled = not running
    model.active = active          # dimmed until this section is the chosen one
    model.prop(scene, "nova3d_paid_model", text="")

    buy = box.row()
    buy.enabled = not running
    buy.operator("nova3d.buy_credits", icon="URL")


def _draw_word_counter(layout, prompt):
    words = len((prompt or "").split())
    row = layout.row()
    row.alignment = "RIGHT"
    over = words > constants.MAX_PROMPT_WORDS
    row.alert = over
    row.label(text=f"{words}/{constants.MAX_PROMPT_WORDS} words")
