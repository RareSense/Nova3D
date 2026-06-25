# SPDX-License-Identifier: MIT
"""Account / credits operators: open web pages, refresh the credit balance.

`Get API Key` and `Buy Credits` simply open the hosted web pages in the user's
browser — the same account and Stripe checkout the web app uses; no credentials
ever leave Blender for these.

`Refresh Credits` fetches the wallet balance on a short-lived worker thread so
the UI never blocks, then writes the count into a WindowManager property.
"""

import queue
import threading

import bpy

from .. import constants
from ..api import client as api_client
from ..api.errors import ApiError
from ..preferences import get_prefs, online_access_ok


def _open_url(url):
    try:
        bpy.ops.wm.url_open(url=url)
        return True
    except Exception:
        return False


class NOVA3D_OT_open_api_key(bpy.types.Operator):
    bl_idname = "nova3d.open_api_key"
    bl_label = "Get / Create API Key"
    bl_description = ("Open the Nova3D web page to sign in or create an account "
                      "and generate your API key")

    def execute(self, context):
        prefs = get_prefs(context)
        web = (prefs.web_base_url if prefs else constants.DEFAULT_WEB_BASE_URL).rstrip("/")
        if _open_url(web + constants.API_KEY_PATH):
            self.report({"INFO"}, "Opened the API-key page in your browser.")
            return {"FINISHED"}
        self.report({"ERROR"}, "Could not open a browser. Visit "
                               f"{web + constants.API_KEY_PATH} manually.")
        return {"CANCELLED"}


class NOVA3D_OT_buy_credits(bpy.types.Operator):
    bl_idname = "nova3d.buy_credits"
    bl_label = "Buy Credits"
    bl_description = "Open the Nova3D subscription page to buy credits"

    def execute(self, context):
        prefs = get_prefs(context)
        web = (prefs.web_base_url if prefs else constants.DEFAULT_WEB_BASE_URL).rstrip("/")
        if _open_url(web + constants.SUBSCRIPTION_PATH):
            self.report({"INFO"}, "Opened the credits page in your browser.")
            return {"FINISHED"}
        self.report({"ERROR"}, "Could not open a browser. Visit "
                               f"{web + constants.SUBSCRIPTION_PATH} manually.")
        return {"CANCELLED"}


class NOVA3D_OT_open_output_folder(bpy.types.Operator):
    bl_idname = "nova3d.open_output_folder"
    bl_label = "Open Last Generation Folder"
    bl_description = "Open the most recent generation's project folder"

    def execute(self, context):
        last_dir = context.window_manager.nova3d_last_dir
        if not last_dir:
            self.report({"WARNING"}, "No generation has completed yet.")
            return {"CANCELLED"}
        if _open_url("file://" + last_dir):
            return {"FINISHED"}
        self.report({"ERROR"}, f"Could not open {last_dir}.")
        return {"CANCELLED"}


class NOVA3D_OT_refresh_credits(bpy.types.Operator):
    bl_idname = "nova3d.refresh_credits"
    bl_label = "Refresh Credits"
    bl_description = "Fetch your current Nova3D credit balance"

    _timer = None
    _queue = None
    _thread = None

    def execute(self, context):
        prefs = get_prefs(context)
        if prefs is None or not prefs.api_key.strip():
            self.report({"WARNING"}, "Set your API key in the add-on preferences first.")
            return {"CANCELLED"}
        if not online_access_ok():
            self.report({"WARNING"}, "Enable Preferences > System > Allow Online "
                                     "Access to use Nova3D.")
            return {"CANCELLED"}

        wm = context.window_manager
        if wm.nova3d_credits_busy:
            return {"CANCELLED"}
        wm.nova3d_credits_busy = True

        self._queue = queue.Queue()
        api_base = prefs.api_base_url
        api_key = prefs.api_key

        def worker(q):
            try:
                client = api_client.Nova3DClient(api_base, api_key)
                balance = client.balance()
                q.put(("ok", int(balance.get("available") or 0)))
            except ApiError as exc:
                q.put(("error", str(exc)))
            except Exception as exc:  # noqa: BLE001
                q.put(("error", str(exc)))

        self._thread = threading.Thread(target=worker, args=(self._queue,),
                                        daemon=True, name="Nova3DCredits")
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
            wm.nova3d_credits = payload
        else:
            self.report({"WARNING"}, f"Could not load credits: {payload}")
        self._finish(context)
        return {"FINISHED"}

    def _finish(self, context):
        wm = context.window_manager
        if self._timer is not None:
            wm.event_timer_remove(self._timer)
            self._timer = None
        wm.nova3d_credits_busy = False
        _tag_redraw(context)

    def cancel(self, context):
        self._finish(context)


def _tag_redraw(context):
    for area in getattr(context.screen, "areas", []) or []:
        if area.type == "VIEW_3D":
            area.tag_redraw()
