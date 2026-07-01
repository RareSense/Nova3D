# SPDX-License-Identifier: MIT
"""Check whether a newer add-on release is available on GitHub.

Runs the lookup on a short-lived worker thread (the UI never blocks) and, on
success, records the result in WindowManager properties that the panel and
preferences read. It needs no API key and works whether or not the user is
signed in. Failures are silent by design — a missed update check must never
nag the user with an error toast.
"""

import queue
import threading

import bpy

from .. import constants
from ..preferences import online_access_ok
from ..services import updates


class NOVA3D_OT_check_updates(bpy.types.Operator):
    bl_idname = "nova3d.check_updates"
    bl_label = "Check for Updates"
    bl_description = "Check GitHub for a newer version of the Nova3D add-on"

    _timer = None
    _queue = None
    _thread = None

    def execute(self, context):
        if not online_access_ok():
            self.report({"WARNING"}, "Enable Preferences > System > Allow Online "
                                     "Access to check for updates.")
            return {"CANCELLED"}

        wm = context.window_manager
        if wm.nova3d_updates_busy:
            return {"CANCELLED"}
        wm.nova3d_updates_busy = True

        self._queue = queue.Queue()

        def worker(q):
            try:
                q.put(("ok", updates.fetch_latest()))
            except Exception as exc:  # noqa: BLE001 — update check must never raise
                q.put(("error", str(exc)))

        self._thread = threading.Thread(target=worker, args=(self._queue,),
                                        daemon=True, name="Nova3DUpdateCheck")
        self._thread.start()

        self._timer = wm.event_timer_add(0.2, window=context.window)
        wm.modal_handler_add(self)
        return {"RUNNING_MODAL"}

    def modal(self, context, event):
        if event.type != "TIMER":
            return {"PASS_THROUGH"}
        try:
            kind, payload = self._queue.get_nowait()
        except queue.Empty:
            return {"PASS_THROUGH"}

        wm = context.window_manager
        if kind == "ok":
            self._apply(wm, payload)
        # On error, leave the previous state untouched and stay silent.
        self._finish(context)
        return {"FINISHED"}

    @staticmethod
    def _apply(wm, latest):
        """Record whether *latest* (version, str, url) beats the installed build."""
        if latest and updates.is_newer(latest[0], constants.ADDON_VERSION):
            _version, version_str, html_url = latest
            wm.nova3d_update_available = True
            wm.nova3d_latest_version = version_str
            wm.nova3d_release_url = html_url
        else:
            wm.nova3d_update_available = False
            wm.nova3d_latest_version = ""
            wm.nova3d_release_url = ""

    def _finish(self, context):
        wm = context.window_manager
        if self._timer is not None:
            wm.event_timer_remove(self._timer)
            self._timer = None
        wm.nova3d_updates_busy = False
        for area in getattr(context.screen, "areas", []) or []:
            if area.type in ("VIEW_3D", "PREFERENCES"):
                area.tag_redraw()

    def cancel(self, context):
        self._finish(context)
