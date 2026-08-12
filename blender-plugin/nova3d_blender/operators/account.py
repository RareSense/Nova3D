# SPDX-License-Identifier: MIT
"""Account / Nova3D Credits operators and external account links.

`Get API Key` and `Buy Nova3D Credits` open hosted pages in the user's
browser — the same account and Stripe checkout the web app uses; no credentials
ever leave Blender for these.

`Refresh Nova3D Credits` fetches the wallet balance and the authoritative
authorization amount for the selected hosted model on a worker thread.
"""

import queue
import threading

import bpy

from .. import constants
from ..api import client as api_client
from ..api.errors import ApiError, ServiceUnavailableError
from ..preferences import get_prefs, online_access_ok
from ..services import pending


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
        web = (prefs.web_base_url if prefs else
               constants.DEFAULT_WEB_BASE_URL).rstrip("/")
        if _open_url(web + constants.API_KEY_PATH):
            self.report({"INFO"}, "Opened the API-key page in your browser.")
            return {"FINISHED"}
        self.report({"ERROR"}, "Could not open a browser. Visit "
                               f"{web + constants.API_KEY_PATH} manually.")
        return {"CANCELLED"}


class NOVA3D_OT_buy_credits(bpy.types.Operator):
    bl_idname = "nova3d.buy_credits"
    bl_label = "Buy Nova3D Credits"
    bl_description = "Open the Nova3D subscription page to buy Nova3D Credits"

    def execute(self, context):
        prefs = get_prefs(context)
        web = (prefs.web_base_url if prefs else
               constants.DEFAULT_WEB_BASE_URL).rstrip("/")
        if _open_url(web + constants.SUBSCRIPTION_PATH):
            self.report({"INFO"}, "Opened the Nova3D Credits page in your browser.")
            return {"FINISHED"}
        self.report({"ERROR"}, "Could not open a browser. Visit "
                               f"{web + constants.SUBSCRIPTION_PATH} manually.")
        return {"CANCELLED"}


class NOVA3D_OT_use_provider_key(bpy.types.Operator):
    bl_idname = "nova3d.use_provider_key"
    bl_label = "Use My API Key"
    bl_description = "Switch this scene to an Anthropic or OpenAI API key"

    def execute(self, context):
        context.scene.nova3d_use_provider_key = True
        _tag_redraw(context)
        return {"FINISHED"}


class NOVA3D_OT_use_credits(bpy.types.Operator):
    bl_idname = "nova3d.use_credits"
    bl_label = "Use Nova3D Credits"
    bl_description = "Switch this scene back to your Nova3D credit balance"

    def execute(self, context):
        context.scene.nova3d_use_provider_key = False
        _tag_redraw(context)
        return {"FINISHED"}


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


class NOVA3D_OT_open_web_run(bpy.types.Operator):
    bl_idname = "nova3d.open_web_run"
    bl_label = "Open in Nova3D App"
    bl_description = ("Open this generation in the Nova3D app; backend runs "
                      "continue there if Blender disconnects")

    def execute(self, context):
        prefs = get_prefs(context)
        web = (prefs.web_base_url if prefs else
               constants.DEFAULT_WEB_BASE_URL).rstrip("/")
        conversation_id = (context.window_manager.nova3d_conversation_id or "").strip()
        if not conversation_id and prefs is not None:
            try:
                records = pending.load_all(prefs.output_dir)
                if records:
                    conversation_id = str(records[-1].get("conversation_id") or "").strip()
            except Exception:
                pass
        url = (f"{web}{constants.WEB_CHAT_PATH}/{conversation_id}"
               if conversation_id else web)
        if _open_url(url):
            return {"FINISHED"}
        self.report({"ERROR"}, f"Could not open a browser. Visit {url} manually.")
        return {"CANCELLED"}


class NOVA3D_OT_copy_workflow_id(bpy.types.Operator):
    bl_idname = "nova3d.copy_workflow_id"
    bl_label = "Copy Workflow ID"
    bl_description = "Copy the current workflow ID to the clipboard"

    def execute(self, context):
        workflow_id = context.window_manager.nova3d_workflow_id
        if not workflow_id:
            self.report({"WARNING"}, "No workflow ID yet.")
            return {"CANCELLED"}
        context.window_manager.clipboard = workflow_id
        self.report({"INFO"}, f"Copied {workflow_id}")
        return {"FINISHED"}


class NOVA3D_OT_refresh_credits(bpy.types.Operator):
    bl_idname = "nova3d.refresh_credits"
    bl_label = "Refresh Nova3D Credits"
    bl_description = "Fetch your current Nova3D Credits balance"

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
        wm.nova3d_credits = -1
        wm.nova3d_required_credits = -1
        wm.nova3d_credit_estimate_model = ""

        self._queue = queue.Queue()
        api_base = prefs.api_base_url
        api_key = prefs.api_key
        key_fingerprint = _key_fingerprint(api_key)
        scene = context.scene
        model_option = None
        if not getattr(scene, "nova3d_use_provider_key", False):
            model_option = next(
                (option for option in constants.HOSTED_MODEL_OPTIONS
                 if option[0] == scene.nova3d_model),
                None,
            )

        def worker(q):
            try:
                client = api_client.Nova3DClient(api_base, api_key)
                balance = client.balance()
                available = _strict_nonnegative_int(balance.get("available"))
                if available is None:
                    raise ApiError("Nova3D returned an unreadable credit balance.")
                required = None
                model_id = ""
                if model_option is not None:
                    estimate = client.estimate(
                        constants.PAID_WORKFLOW_NAME, model_option[2])
                    required = _strict_nonnegative_int(
                        estimate.get("authorized_budget"))
                    if required is None:
                        raise ApiError("Nova3D returned an unreadable model price.")
                    model_id = model_option[0]
                q.put(("ok", (available, required, model_id,
                              api_base, key_fingerprint)))
            except ServiceUnavailableError as exc:
                # Nova3D unreachable / 5xx — a health signal, not a key problem.
                q.put(("down", str(exc)))
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
            available, required, model_id, api_base, key_fingerprint = payload
            prefs = get_prefs(context)
            current_model = (context.scene.nova3d_model
                             if not context.scene.nova3d_use_provider_key else "")
            still_current = bool(
                prefs
                and prefs.api_base_url == api_base
                and _key_fingerprint(prefs.api_key) == key_fingerprint
                and current_model == model_id
            )
            if still_current:
                wm.nova3d_credits = available
                wm.nova3d_required_credits = required if required is not None else -1
                wm.nova3d_credit_estimate_model = model_id
                wm.nova3d_service_down = False
            elif not context.scene.nova3d_use_provider_key:
                # The model/account changed while the worker was running. Its
                # quote must never enable Generate for a different selection.
                self._finish(context)
                try:
                    bpy.ops.nova3d.refresh_credits("INVOKE_DEFAULT")
                except Exception:
                    pass
                return {"FINISHED"}
        elif kind == "down":
            # Don't spam a toast — the panel shows a persistent "unreachable"
            # banner with a Retry button instead.
            wm.nova3d_service_down = True
            wm.nova3d_credits = -1
            wm.nova3d_required_credits = -1
            wm.nova3d_credit_estimate_model = ""
        else:
            wm.nova3d_service_down = False
            wm.nova3d_credits = -1
            wm.nova3d_required_credits = -1
            wm.nova3d_credit_estimate_model = ""
            self.report({"WARNING"}, f"Could not load Nova3D Credits: {payload}")
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


def _strict_nonnegative_int(value):
    if isinstance(value, bool) or value is None:
        return None
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed >= 0 else None


def _key_fingerprint(value):
    import hashlib
    return hashlib.sha256((value or "").encode("utf-8")).hexdigest()[:16]
