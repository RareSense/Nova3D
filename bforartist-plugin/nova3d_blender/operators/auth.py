# SPDX-License-Identifier: MIT
"""Authentication operators: Google sign-in, manual key entry, sign-out.

  * NOVA3D_OT_sign_in       — non-blocking modal that runs the browser sign-in
    worker and stores the resulting token. The primary, one-click path.
  * NOVA3D_OT_enter_api_key — an in-panel popup to paste a key (the fallback for
    headless/locked-down setups). Replaces the old "open Preferences" round-trip.
  * NOVA3D_OT_sign_out      — forget the stored credential.

Only one sign-in runs at a time, and never alongside a generation.
"""

import queue

import bpy

from ..preferences import (
    clear_credential, get_prefs, online_access_ok, set_credential)
from ..services.signin import SignInJob
from . import generate

# Handle to the active sign-in job (so the modal/Cancel can reach it).
_active_signin = None


def is_signing_in():
    return _active_signin is not None


class NOVA3D_OT_sign_in(bpy.types.Operator):
    bl_idname = "nova3d.sign_in"
    bl_label = "Sign in with Google"
    bl_description = ("Sign in through your browser — no API key to copy. "
                     "Opens app.nova3d.xyz and finishes automatically")

    _timer = None
    _queue = None
    _job = None

    def invoke(self, context, event):
        global _active_signin
        if generate.is_generating():
            self.report({"WARNING"}, "A generation is running — try again after it finishes.")
            return {"CANCELLED"}
        if _active_signin is not None:
            self.report({"WARNING"}, "Sign-in is already in progress.")
            return {"CANCELLED"}
        prefs = get_prefs(context)
        if prefs is None:
            self.report({"ERROR"}, "Add-on preferences are unavailable.")
            return {"CANCELLED"}
        if not online_access_ok():
            self.report({"ERROR"}, "Enable Preferences > System > Allow Online Access first.")
            return {"CANCELLED"}

        self._queue = queue.Queue()
        self._job = SignInJob(
            api_base_url=prefs.api_base_url, web_base_url=prefs.web_base_url,
            queue=self._queue)
        _active_signin = self._job

        wm = context.window_manager
        wm.nova3d_signing_in = True
        wm.nova3d_status = "Starting sign-in…"
        self._job.start()
        self._timer = wm.event_timer_add(0.25, window=context.window)
        wm.modal_handler_add(self)
        _tag_redraw(context)
        return {"RUNNING_MODAL"}

    def modal(self, context, event):
        if event.type == "ESC":
            if self._job is not None:
                self._job.cancel()
                context.window_manager.nova3d_status = "Cancelling sign-in…"
                _tag_redraw(context)
            return {"RUNNING_MODAL"}
        if event.type != "TIMER":
            return {"PASS_THROUGH"}
        while True:
            try:
                kind, payload = self._queue.get_nowait()
            except queue.Empty:
                break
            result = self._handle_event(context, kind, payload)
            if result is not None:
                return result
        return {"PASS_THROUGH"}

    def _handle_event(self, context, kind, payload):
        wm = context.window_manager
        if kind == "status":
            wm.nova3d_status = payload
            _tag_redraw(context)
        elif kind == "signed_in":
            prefs = get_prefs(context)
            if prefs is not None and payload and payload.get("token"):
                set_credential(prefs, payload["token"], source="sign_in",
                               expires_at=payload.get("expires_at"))
                wm.nova3d_credits = -1  # force a fresh balance fetch
                self.report({"INFO"}, "Signed in to Nova3D.")
        elif kind == "error":
            self.report({"ERROR"}, payload)
            wm.nova3d_status = payload
            self._finish(context)
            return {"CANCELLED"}
        elif kind == "finished":
            prefs = get_prefs(context)
            wm.nova3d_status = "Signed in." if (prefs and prefs.api_key.strip()) else ""
            self._finish(context)
            self._refresh_credits(context)
            return {"FINISHED"}
        return None

    def _finish(self, context):
        global _active_signin
        wm = context.window_manager
        if self._timer is not None:
            wm.event_timer_remove(self._timer)
            self._timer = None
        wm.nova3d_signing_in = False
        _active_signin = None
        self._job = None
        _tag_redraw(context)

    def _refresh_credits(self, context):
        try:
            bpy.ops.nova3d.refresh_credits("INVOKE_DEFAULT")
        except Exception:
            context.window_manager.nova3d_credits = -1

    def cancel(self, context):
        if self._job is not None:
            self._job.cancel()
        self._finish(context)


class NOVA3D_OT_enter_api_key(bpy.types.Operator):
    bl_idname = "nova3d.enter_api_key"
    bl_label = "Enter API Key"
    bl_description = "Paste a Nova3D API key (alternative to signing in)"

    api_key: bpy.props.StringProperty(
        name="API Key",
        description="Your Nova3D API key (starts with n3d_)",
        default="",
        subtype="PASSWORD",
    )

    def invoke(self, context, event):
        prefs = get_prefs(context)
        self.api_key = prefs.api_key if prefs else ""
        return context.window_manager.invoke_props_dialog(self, width=420)

    def draw(self, context):
        col = self.layout.column()
        col.label(text="Paste your Nova3D API key (n3d_…):")
        col.prop(self, "api_key", text="")
        col.operator("nova3d.open_api_key", text="Don't have one? Create a key",
                     icon="URL", emboss=False)

    def execute(self, context):
        prefs = get_prefs(context)
        if prefs is None:
            self.report({"ERROR"}, "Add-on preferences are unavailable.")
            return {"CANCELLED"}
        key = (self.api_key or "").strip()
        if not key:
            self.report({"WARNING"}, "No key entered.")
            return {"CANCELLED"}
        set_credential(prefs, key, source="manual")
        context.window_manager.nova3d_credits = -1
        try:
            bpy.ops.nova3d.refresh_credits("INVOKE_DEFAULT")
        except Exception:
            pass
        self.report({"INFO"}, "API key saved.")
        _tag_redraw(context)
        return {"FINISHED"}


class NOVA3D_OT_sign_out(bpy.types.Operator):
    bl_idname = "nova3d.sign_out"
    bl_label = "Sign Out"
    bl_description = "Forget the stored Nova3D credential on this machine"

    def execute(self, context):
        prefs = get_prefs(context)
        if prefs is not None:
            clear_credential(prefs)
        context.window_manager.nova3d_credits = -1
        context.window_manager.nova3d_status = ""
        self.report({"INFO"}, "Signed out.")
        _tag_redraw(context)
        return {"FINISHED"}


def _tag_redraw(context):
    for area in getattr(context.screen, "areas", []) or []:
        if area.type == "VIEW_3D":
            area.tag_redraw()
