# SPDX-License-Identifier: MIT
"""Generate + Resume operators — non-blocking modals that drive worker jobs.

Both share `_JobModalMixin`, which runs one or more `GenerationJob`s
sequentially: it drains the worker's event queue each timer tick, updates the
status line, and performs the Blender-side import on the main thread when a
worker signals `done`.

  * NOVA3D_OT_generate — starts a fresh generation.
  * NOVA3D_OT_resume   — re-attaches to every pending (interrupted) generation
    on disk and finishes it: imports the model and writes web history. This is
    what makes a run survive a network drop, a laptop sleep, or closing Blender.

Only one runner is active at a time (module-level `_active_job`).
"""

import queue

import bpy

from .. import constants
from .. import properties
from ..preferences import get_prefs, online_access_ok
from ..services import images as image_service
from ..services import pending
from ..services import provider_access
from ..services.generation import GenerationJob, GenerationParams
from ..scene_io import importer

# Handle to the currently running job, so the Cancel operator can reach it.
_active_job = None


def is_generating():
    return _active_job is not None


def update_pending_count(context):
    """Refresh the cached count of interrupted generations awaiting resume."""
    prefs = get_prefs(context)
    wm = context.window_manager
    if prefs is None:
        wm.nova3d_pending = 0
        return
    try:
        wm.nova3d_pending = pending.count(prefs.output_dir)
    except Exception:
        wm.nova3d_pending = 0


class _JobModalMixin:
    """Modal event pump shared by the Generate and Resume operators."""

    _timer = None
    _queue = None
    _job = None
    _factories = None  # remaining job factories, for sequential runs

    def _start_jobs(self, context, factories):
        """Begin a (non-empty) list of job factories: fn(queue) -> GenerationJob."""
        self._factories = list(factories)
        wm = context.window_manager
        wm.nova3d_running = True
        self._timer = wm.event_timer_add(0.25, window=context.window)
        wm.modal_handler_add(self)
        self._start_next(context)
        _tag_redraw(context)
        return {"RUNNING_MODAL"}

    def _start_next(self, context):
        global _active_job
        factory = self._factories.pop(0)
        self._queue = queue.Queue()
        self._job = factory(self._queue)
        _active_job = self._job
        wm = context.window_manager
        wm.nova3d_status = "Starting..."
        wm.nova3d_workflow_id = ""
        wm.nova3d_conversation_id = ""
        self._job.start()

    def modal(self, context, event):
        if event.type == "ESC":
            if self._job is not None:
                self._job.cancel()
                context.window_manager.nova3d_status = "Cancelling..."
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
        elif kind == "workflow":
            wm.nova3d_workflow_id = payload or ""
            _tag_redraw(context)
        elif kind == "conversation":
            wm.nova3d_conversation_id = payload or ""
            _tag_redraw(context)
        elif kind == "done":
            self._import_asset(context, payload)
        elif kind in ("error", "detached", "finished"):
            if kind == "error":
                self.report({"ERROR"}, payload)
                wm.nova3d_status = payload
            elif kind == "detached":
                self.report({"WARNING"}, payload)
                wm.nova3d_status = payload
            elif not wm.nova3d_status or wm.nova3d_status.endswith("..."):
                wm.nova3d_status = "Done."
            # More queued jobs (sequential resume) → start the next one.
            if self._factories:
                self._start_next(context)
                return None
            self._finish(context)
            self._refresh_credits(context)
            return {"FINISHED"}
        return None

    def _import_asset(self, context, payload):
        wm = context.window_manager
        glb_path = payload.get("glb_path")
        slug = payload.get("slug") or "model"
        try:
            collection = importer.import_generation(
                context, glb_path=glb_path, slug=slug) if glb_path else None
            importer.load_code_text(slug, payload.get("code_text"))
        except Exception as exc:  # noqa: BLE001 - importing must never crash Blender
            self.report({"WARNING"}, f"Model saved, but import failed: {exc}")
            collection = None
        wm.nova3d_last_dir = payload.get("project_dir") or ""
        label = payload.get("model_label") or "model"
        if collection is not None:
            wm.nova3d_status = f"Imported '{label}'. Files saved to disk."
            self.report({"INFO"}, f"Nova3D model ready: {wm.nova3d_last_dir}")
        else:
            wm.nova3d_status = f"Saved '{label}' to disk (see project folder)."
        warning = payload.get("warning_message")
        if warning:
            wm.nova3d_status = warning
            self.report({"WARNING"}, warning)
        _tag_redraw(context)

    def _finish(self, context):
        global _active_job
        wm = context.window_manager
        if self._timer is not None:
            wm.event_timer_remove(self._timer)
            self._timer = None
        wm.nova3d_running = False
        _active_job = None
        self._job = None
        self._factories = None
        update_pending_count(context)
        _tag_redraw(context)

    def _refresh_credits(self, context):
        try:
            bpy.ops.nova3d.refresh_credits("INVOKE_DEFAULT")
        except Exception:
            context.window_manager.nova3d_credits = -1  # force a manual refresh

    def cancel(self, context):
        if self._job is not None:
            self._job.cancel()
        self._finish(context)


class NOVA3D_OT_generate(bpy.types.Operator, _JobModalMixin):
    bl_idname = "nova3d.generate"
    bl_label = "Generate"
    bl_description = ("Generate a 3D model using Nova3D Credits or a verified "
                      "Anthropic/OpenAI key")

    def invoke(self, context, event):
        if is_generating():
            self.report({"WARNING"}, "A generation is already running.")
            return {"CANCELLED"}

        prefs = get_prefs(context)
        if prefs is None or not prefs.api_key.strip():
            self.report({"ERROR"},
                        "Set your Nova3D API key in the add-on preferences first.")
            return {"CANCELLED"}
        if not online_access_ok():
            self.report({"ERROR"}, "Enable Preferences > System > Allow Online "
                                   "Access to use Nova3D.")
            return {"CANCELLED"}

        scene = context.scene
        prompt = (scene.nova3d_prompt or "").strip()
        image_paths = [img.path for img in scene.nova3d_images if img.path]
        if not prompt and not image_paths:
            self.report({"ERROR"}, "Enter a prompt or attach a reference image.")
            return {"CANCELLED"}
        if prompt and len(prompt.split()) > constants.MAX_PROMPT_WORDS:
            self.report({"ERROR"},
                        f"Prompt must be {constants.MAX_PROMPT_WORDS} words or fewer.")
            return {"CANCELLED"}

        access_mode = properties.access_mode(scene)
        available = properties.available_model_options(context, access_mode)
        model_option = next(
            (option for option in available if option[0] == scene.nova3d_model),
            None,
        )
        if model_option is None:
            self.report({"ERROR"}, "Connect a provider key, or use Nova3D Credits.")
            return {"CANCELLED"}

        provider = constants.provider_for_option(model_option)
        provider_key = ""
        if access_mode == constants.BILLING_PROVIDER_KEY:
            if not provider or not provider_access.validation_is_current(prefs, provider):
                self.report({"ERROR"}, "Test the selected provider key and model access first.")
                return {"CANCELLED"}
            provider_key = provider_access.provider_key(prefs, provider)
        else:
            wm = context.window_manager
            quote_matches = wm.nova3d_credit_estimate_model == model_option[0]
            required = wm.nova3d_required_credits
            balance = wm.nova3d_credits
            if not quote_matches or required < 0 or balance < 0:
                self.report({"ERROR"}, "Check your Nova3D credit balance first.")
                try:
                    bpy.ops.nova3d.refresh_credits("INVOKE_DEFAULT")
                except Exception:
                    pass
                return {"CANCELLED"}
            if balance < required:
                self.report(
                    {"ERROR"},
                    f"This model needs {required} credits; you have {balance}. "
                    "Buy credits or use your own API key.")
                return {"CANCELLED"}

        # Encode reference images now, on the main thread (bpy is not thread-safe).
        data_urls = []
        if image_paths:
            data_urls, skipped = image_service.encode_references(image_paths)
            for path, reason in skipped:
                self.report({"WARNING"}, f"Skipped image ({reason}).")

        params = GenerationParams(
            api_base_url=prefs.api_base_url,
            api_key=prefs.api_key.strip(),
            prompt=prompt,
            image_data_urls=data_urls,
            model_option=model_option,
            output_root=prefs.output_dir,
            billing_mode=access_mode,
            provider=provider,
            provider_api_key=provider_key,
        )
        return self._start_jobs(context, [lambda q: GenerationJob(params, q)])


class NOVA3D_OT_resume(bpy.types.Operator, _JobModalMixin):
    bl_idname = "nova3d.resume"
    bl_label = "Resume Pending"
    bl_description = ("Finish generations that were interrupted (network drop, "
                     "closed Blender, etc.) by re-attaching to them")

    def execute(self, context):
        if is_generating():
            self.report({"WARNING"}, "A generation is already running.")
            return {"CANCELLED"}

        prefs = get_prefs(context)
        if prefs is None or not prefs.api_key.strip():
            self.report({"WARNING"}, "Set your Nova3D API key in preferences first.")
            return {"CANCELLED"}
        if not online_access_ok():
            self.report({"WARNING"}, "Enable Preferences > System > Allow Online "
                                     "Access to resume.")
            return {"CANCELLED"}

        records = pending.load_all(prefs.output_dir)
        if not records:
            self.report({"INFO"}, "No pending generations to resume.")
            update_pending_count(context)
            return {"CANCELLED"}

        api_base = prefs.api_base_url
        api_key = prefs.api_key.strip()

        def make_factory(record):
            return lambda q: GenerationJob.for_resume(
                record, api_base_url=api_base, api_key=api_key, queue=q)

        factories = [make_factory(rec) for rec in records]
        self.report({"INFO"}, f"Resuming {len(factories)} pending generation(s).")
        return self._start_jobs(context, factories)


class NOVA3D_OT_cancel(bpy.types.Operator):
    bl_idname = "nova3d.cancel"
    bl_label = "Stop Waiting in Blender"
    bl_description = ("Detach Blender from this run; the backend generation "
                      "continues and remains available in the Nova3D app")

    def execute(self, context):
        if _active_job is not None:
            _active_job.cancel()
            context.window_manager.nova3d_status = "Stopping local wait…"
            self.report({"INFO"}, "Stopping Blender's wait; the backend run continues.")
            return {"FINISHED"}
        self.report({"WARNING"}, "No generation is running.")
        return {"CANCELLED"}


def _tag_redraw(context):
    for area in getattr(context.screen, "areas", []) or []:
        if area.type == "VIEW_3D":
            area.tag_redraw()
