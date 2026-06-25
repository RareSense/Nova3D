# SPDX-License-Identifier: MIT
"""The Generate operator — a non-blocking modal that drives one generation.

Flow:
  * `invoke` validates inputs, encodes reference images (main thread), launches a
    `GenerationJob` worker thread, and starts a modal timer. It returns
    immediately so Blender stays fully responsive (the spec's "non-blocking
    experience").
  * `modal` drains the worker's event queue each timer tick, updates the status
    line, and — when the worker signals `done` — performs the Blender-side
    import (GLB + text datablock + collection hiding) on the main thread.

Only one generation runs at a time. A module-level handle lets the separate
Cancel operator signal the active job.
"""

import queue

import bpy

from .. import constants
from ..preferences import get_prefs, online_access_ok
from ..services import images as image_service
from ..services.generation import GenerationJob, GenerationParams
from ..scene_io import importer

# Handle to the currently running job, so the Cancel operator can reach it.
_active_job = None


def is_generating():
    return _active_job is not None


class NOVA3D_OT_generate(bpy.types.Operator):
    bl_idname = "nova3d.generate"
    bl_label = "Generate"
    bl_description = "Generate a 3D model from your prompt using Nova3D credits"

    _timer = None
    _queue = None
    _job = None

    # ── launch ───────────────────────────────────────────────────────────────
    def invoke(self, context, event):
        global _active_job

        wm = context.window_manager
        if wm.nova3d_running or _active_job is not None:
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

        # Encode reference images now, on the main thread (bpy is not thread-safe).
        data_urls, skipped = ([], [])
        if image_paths:
            data_urls, skipped = image_service.encode_references(image_paths)
            for path, reason in skipped:
                self.report({"WARNING"}, f"Skipped image ({reason}).")

        params = GenerationParams(
            api_base_url=prefs.api_base_url,
            api_key=prefs.api_key.strip(),
            prompt=prompt,
            image_data_urls=data_urls,
            model_option=constants.model_option_by_id(scene.nova3d_model),
            output_root=prefs.output_dir,
        )

        self._queue = queue.Queue()
        self._job = GenerationJob(params, self._queue)
        _active_job = self._job

        wm.nova3d_running = True
        wm.nova3d_status = "Starting generation..."
        wm.nova3d_uv_status = ""
        self._job.start()

        self._timer = wm.event_timer_add(0.25, window=context.window)
        wm.modal_handler_add(self)
        _tag_redraw(context)
        return {"RUNNING_MODAL"}

    # ── event pump ───────────────────────────────────────────────────────────
    def modal(self, context, event):
        if event.type == "ESC":
            if self._job is not None:
                self._job.cancel()
                context.window_manager.nova3d_status = "Cancelling..."
                _tag_redraw(context)
            return {"RUNNING_MODAL"}

        if event.type != "TIMER":
            return {"PASS_THROUGH"}

        # Drain everything the worker has queued since the last tick.
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
        elif kind == "uv_status":
            wm.nova3d_uv_status = payload
            _tag_redraw(context)
        elif kind == "uv_done":
            count = sum(s.get("atlas_count", 0) for s in (payload or {}).get("sets", []))
            wm.nova3d_uv_status = f"UV maps ready ({count} atlas file(s))."
            _tag_redraw(context)
        elif kind == "done":
            self._import_asset(context, payload)
        elif kind == "error":
            self.report({"ERROR"}, payload)
            wm.nova3d_status = payload
            self._finish(context)
            return {"CANCELLED"}
        elif kind == "finished":
            if not wm.nova3d_status or wm.nova3d_status.endswith("..."):
                wm.nova3d_status = "Done."
            self._finish(context)
            self._refresh_credits(context)
            return {"FINISHED"}
        return None

    # ── main-thread Blender work ─────────────────────────────────────────────
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
        _tag_redraw(context)

    # ── teardown ─────────────────────────────────────────────────────────────
    def _finish(self, context):
        global _active_job
        wm = context.window_manager
        if self._timer is not None:
            wm.event_timer_remove(self._timer)
            self._timer = None
        wm.nova3d_running = False
        _active_job = None
        self._job = None
        _tag_redraw(context)

    def _refresh_credits(self, context):
        # Credits changed; refresh the cached balance without blocking.
        try:
            bpy.ops.nova3d.refresh_credits("INVOKE_DEFAULT")
        except Exception:
            context.window_manager.nova3d_credits = -1  # force a manual refresh

    def cancel(self, context):
        if self._job is not None:
            self._job.cancel()
        self._finish(context)


class NOVA3D_OT_cancel(bpy.types.Operator):
    bl_idname = "nova3d.cancel"
    bl_label = "Cancel Generation"
    bl_description = "Stop the running generation"

    def execute(self, context):
        if _active_job is not None:
            _active_job.cancel()
            context.window_manager.nova3d_status = "Cancelling..."
            self.report({"INFO"}, "Cancelling the current generation.")
            return {"FINISHED"}
        self.report({"WARNING"}, "No generation is running.")
        return {"CANCELLED"}


def _tag_redraw(context):
    for area in getattr(context.screen, "areas", []) or []:
        if area.type == "VIEW_3D":
            area.tag_redraw()
