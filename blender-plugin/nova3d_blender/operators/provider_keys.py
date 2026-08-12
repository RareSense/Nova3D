# SPDX-License-Identifier: MIT
"""Provider-key setup, validation, and account links.

Validation is modal and non-blocking: the network work runs on a background
thread, while only the modal callback touches Blender preferences/UI state.
"""

import queue
import threading

import bpy

from .. import constants, properties
from ..preferences import get_prefs, online_access_ok
from ..services import provider_access


def _open_url(url):
    try:
        bpy.ops.wm.url_open(url=url)
        return True
    except Exception:
        return False


def _key_attr(provider):
    return ("anthropic_api_key" if provider == constants.PROVIDER_ANTHROPIC
            else "openai_api_key")


def _funding_attr(provider):
    return ("anthropic_funding_confirmed" if provider == constants.PROVIDER_ANTHROPIC
            else "openai_funding_confirmed")


def _validation_attrs(provider):
    if provider == constants.PROVIDER_ANTHROPIC:
        return ("anthropic_validation_fingerprint",
                "anthropic_available_models",
                "anthropic_validation_message")
    return ("openai_validation_fingerprint",
            "openai_available_models",
            "openai_validation_message")


class NOVA3D_OT_test_provider_key(bpy.types.Operator):
    bl_idname = "nova3d.test_provider_key"
    bl_label = "Test API Key & Model Access"
    bl_description = ("Verify the key, provider funding, and exact Nova3D model "
                      "access before starting a generation")

    provider: bpy.props.EnumProperty(items=(
        (constants.PROVIDER_ANTHROPIC, "Anthropic", "Test Anthropic access"),
        (constants.PROVIDER_OPENAI, "OpenAI", "Test OpenAI access"),
    ))

    _timer = None
    _queue = None
    _thread = None
    _tested_fingerprint = ""

    def execute(self, context):
        prefs = get_prefs(context)
        # Copy the RNA value before starting the worker. Background threads
        # must never read properties from a Blender operator instance.
        provider = str(self.provider)
        label = provider_access.provider_label(provider)
        if prefs is None:
            self.report({"ERROR"}, "Nova3D preferences are unavailable.")
            return {"CANCELLED"}
        if not online_access_ok():
            self.report({"ERROR"}, "Enable Preferences > System > Allow Online Access first.")
            return {"CANCELLED"}
        key = (getattr(prefs, _key_attr(provider), "") or "").strip()
        if not key:
            self.report({"ERROR"}, f"Enter your {label} API key first.")
            return {"CANCELLED"}
        if not bool(getattr(prefs, _funding_attr(provider), False)):
            self.report(
                {"ERROR"},
                f"Confirm that you added at least ${constants.RECOMMENDED_PROVIDER_BALANCE_USD} first.")
            return {"CANCELLED"}

        wm = context.window_manager
        if wm.nova3d_provider_test_busy:
            self.report({"INFO"}, "A provider access test is already running.")
            return {"CANCELLED"}
        wm.nova3d_provider_test_busy = True
        wm.nova3d_provider_test_name = provider
        self._tested_fingerprint = provider_access.key_fingerprint(key)
        _set_validation_message(prefs, provider, f"Testing {label}…")

        self._queue = queue.Queue()

        def worker(result_queue):
            try:
                result_queue.put(("ok", provider_access.validate_provider(
                    provider, key)))
            except provider_access.ProviderAccessError as exc:
                result_queue.put(("error", exc))
            except Exception:
                result_queue.put(("error", provider_access.ProviderAccessError(
                    f"Could not complete the {label} access test. Your key was not sent to a Nova3D workflow.",
                    provider=provider, category="unexpected")))

        self._thread = threading.Thread(
            target=worker, args=(self._queue,), daemon=True,
            name=f"Nova3D{label}KeyTest")
        self._thread.start()
        self._timer = wm.event_timer_add(0.2, window=context.window)
        wm.modal_handler_add(self)
        _tag_redraw(context)
        return {"RUNNING_MODAL"}

    def modal(self, context, event):
        if event.type != "TIMER":
            return {"PASS_THROUGH"}
        try:
            kind, payload = self._queue.get_nowait()
        except queue.Empty:
            return {"PASS_THROUGH"}

        prefs = get_prefs(context)
        if prefs is not None:
            fingerprint_attr, models_attr, message_attr = _validation_attrs(self.provider)
            current_key = getattr(prefs, _key_attr(self.provider), "")
            if provider_access.key_fingerprint(current_key) != self._tested_fingerprint:
                setattr(prefs, message_attr, "Key changed during the test. Test the new key again.")
                properties.ensure_valid_model_selection(context)
                self._finish(context)
                return {"FINISHED"}
            if kind == "ok":
                setattr(prefs, fingerprint_attr, self._tested_fingerprint)
                setattr(prefs, models_attr, ",".join(payload.available_model_ids))
                names = ", ".join(payload.available_model_ids)
                setattr(prefs, message_attr, f"Ready — {names}")
                self.report({"INFO"},
                            f"{provider_access.provider_label(self.provider)} access verified.")
            else:
                # A local network/provider outage does not revoke a previously
                # valid key. Definite key/billing/access failures do.
                was_current = provider_access.validation_is_current(
                    prefs, self.provider)
                if payload.category != "network":
                    setattr(prefs, fingerprint_attr, "")
                    setattr(prefs, models_attr, "")
                message = str(payload)
                if payload.category == "network" and was_current:
                    message = f"Last verified access kept. {message}"
                setattr(prefs, message_attr, message)
                self.report({"ERROR"}, str(payload))

        properties.ensure_valid_model_selection(context)
        self._finish(context)
        return {"FINISHED"}

    def _finish(self, context):
        wm = context.window_manager
        if self._timer is not None:
            wm.event_timer_remove(self._timer)
            self._timer = None
        wm.nova3d_provider_test_busy = False
        wm.nova3d_provider_test_name = ""
        _tag_redraw(context)

    def cancel(self, context):
        self._finish(context)


class NOVA3D_OT_clear_provider_key(bpy.types.Operator):
    bl_idname = "nova3d.clear_provider_key"
    bl_label = "Remove Provider Key"
    bl_description = "Forget this provider key and remove its models from the picker"

    provider: bpy.props.EnumProperty(items=(
        (constants.PROVIDER_ANTHROPIC, "Anthropic", "Remove Anthropic key"),
        (constants.PROVIDER_OPENAI, "OpenAI", "Remove OpenAI key"),
    ))

    def execute(self, context):
        prefs = get_prefs(context)
        if prefs is None:
            return {"CANCELLED"}
        setattr(prefs, _key_attr(self.provider), "")
        properties.ensure_valid_model_selection(context)
        self.report({"INFO"}, f"Removed the {provider_access.provider_label(self.provider)} key.")
        _tag_redraw(context)
        return {"FINISHED"}


class NOVA3D_OT_open_provider_page(bpy.types.Operator):
    bl_idname = "nova3d.open_provider_page"
    bl_label = "Open Provider Setup"
    bl_description = "Open the provider's official setup page"

    destination: bpy.props.EnumProperty(items=(
        ("anthropic_keys", "Anthropic keys", "Create an Anthropic key"),
        ("anthropic_billing", "Anthropic billing", "Fund Anthropic usage credits"),
        ("openai_keys", "OpenAI keys", "Create an OpenAI key"),
        ("openai_billing", "OpenAI billing", "Fund the OpenAI API account"),
        ("openai_models", "OpenAI model access", "Enable models and check limits"),
    ))

    def execute(self, _context):
        urls = {
            "anthropic_keys": constants.ANTHROPIC_KEYS_URL,
            "anthropic_billing": constants.ANTHROPIC_BILLING_URL,
            "openai_keys": constants.OPENAI_KEYS_URL,
            "openai_billing": constants.OPENAI_BILLING_URL,
            "openai_models": constants.OPENAI_MODEL_ACCESS_URL,
        }
        url = urls.get(self.destination)
        if url and _open_url(url):
            return {"FINISHED"}
        self.report({"ERROR"}, f"Could not open a browser. Visit {url} manually.")
        return {"CANCELLED"}


def _set_validation_message(prefs, provider, message):
    _fingerprint, _models, message_attr = _validation_attrs(provider)
    setattr(prefs, message_attr, message)


def _tag_redraw(context):
    for area in getattr(context.screen, "areas", []) or []:
        if area.type == "VIEW_3D":
            area.tag_redraw()
