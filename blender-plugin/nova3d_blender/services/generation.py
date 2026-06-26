# SPDX-License-Identifier: MIT
"""The end-to-end generation pipeline, run on a background worker thread.

The worker performs every blocking step (preflight, start, poll, download,
history, optional UV maps) and reports progress to the operator through a
thread-safe queue. It NEVER touches `bpy` — the only Blender-side work
(importing the GLB, creating the text datablock, hiding old collections) happens
on the main thread in `operators/generate.py` when it receives the `done` event.

Event protocol (queue items are `(kind, payload)`):
    ("status",   str)      progress line update
    ("done",     dict)     model is on disk; main thread should import it now
    ("uv_status",str)      UV sub-step progress
    ("uv_done",  dict)     UV atlases written
    ("error",    str)      terminal failure (user-safe message)
    ("finished", None)     the job is fully complete (always last on success)
"""

import threading
import time

from .. import constants
from ..api import client as api_client
from ..api.errors import ApiError, AuthError
from . import history, project_store, uv_maps


class GenerationParams:
    """Immutable inputs for one generation, assembled on the main thread."""

    def __init__(self, *, api_base_url, api_key, prompt, image_data_urls,
                 model_option, output_root):
        self.api_base_url = api_base_url
        self.api_key = api_key
        self.prompt = (prompt or "").strip()
        self.image_data_urls = list(image_data_urls or [])
        self.model_option = model_option  # (id, label, tier, credits, badge)
        self.output_root = output_root

    @property
    def has_image(self):
        return bool(self.image_data_urls)


class GenerationJob(threading.Thread):
    """Runs one generation to completion and emits progress events."""

    def __init__(self, params, queue):
        super().__init__(daemon=True, name="Nova3DGeneration")
        self._params = params
        self._queue = queue
        self._cancel = threading.Event()
        self._client = api_client.Nova3DClient(params.api_base_url, params.api_key)

    # ── public control ───────────────────────────────────────────────────────
    def cancel(self):
        self._cancel.set()

    @property
    def cancelled(self):
        return self._cancel.is_set()

    # ── event helpers ────────────────────────────────────────────────────────
    def _emit(self, kind, payload=None):
        self._queue.put((kind, payload))

    def _status(self, message):
        self._emit("status", message)

    # ── thread entry point ───────────────────────────────────────────────────
    def run(self):
        try:
            self._run_pipeline()
        except AuthError as exc:
            self._emit("error", str(exc))
        except ApiError as exc:
            self._emit("error", str(exc))
        except Exception as exc:  # noqa: BLE001 - last-resort guard for the thread
            self._emit("error", f"Generation failed unexpectedly: {exc}")

    # ── pipeline ─────────────────────────────────────────────────────────────
    def _run_pipeline(self):
        params = self._params
        model_id, model_label, tier, _credits, _badge = params.model_option

        # 1. Preflight: service readiness.
        self._status("Checking the generation service...")
        readiness = self._client.readiness(constants.WORKFLOW_NAME)
        if not readiness.get("ready", False):
            reason = readiness.get("reason")
            self._emit("error", _readiness_message(reason))
            return

        # 2. Preflight: credits estimate vs. wallet balance.
        self._status("Estimating credits...")
        estimate = self._client.estimate(constants.WORKFLOW_NAME, tier)
        required = int(estimate.get("authorized_budget")
                       or estimate.get("projected_max_hold") or 0)
        balance = self._client.balance()
        available = _int(balance.get("available"))
        if available is None:
            self._emit("error", "Could not confirm your credit balance. "
                                "Open Buy Credits, refresh, and try again.")
            return
        if available < required:
            self._emit("error",
                       f"This model needs {required} credits, but you have "
                       f"{available}. Use 'Buy Credits' and try again.")
            return

        if self._cancel.is_set():
            self._emit("finished")
            return

        # 3. Create the conversation so this generation shows in web history.
        self._status("Creating session...")
        conversation = self._client.create_conversation(
            history.conversation_title(params.prompt))
        conversation_id = conversation.get("id") or conversation.get("conversation_id")

        # 4. Start the workflow (linked to the conversation).
        now_us = int(time.time() * 1_000_000)
        workflow_id = f"state-{now_us}"
        self._status("Starting generation...")
        payload = self._build_payload(tier)
        try:
            workflow_id = self._client.start_generation(
                constants.WORKFLOW_NAME, request_id=workflow_id, payload=payload,
                return_nodes=constants.GENERATION_RETURN_NODES,
                conversation_link=history.start_link(conversation_id) if conversation_id else None,
            )
        except AuthError:
            raise
        except ApiError as exc:
            # A transport/timeout error (no HTTP status) may still have started
            # the workflow — poll the id we requested, matching the web client's
            # `_mayHaveStarted`. A real HTTP error (e.g. 402 insufficient credits)
            # must surface instead of silently charging the user.
            if exc.status is not None:
                raise
            # keep the client-generated workflow_id and fall through to polling.

        # Surface the workflow id immediately so the user can track the request
        # (and find it in logs/support) even if it later fails.
        self._emit("workflow", workflow_id)

        # 5. Poll status to completion.
        if not self._poll_status(workflow_id):
            return  # cancelled / errored already emitted

        # 6. Fetch + parse the result.
        self._status("Finalizing the model...")
        parsed = self._fetch_result(workflow_id)
        if parsed is None:
            return
        if parsed.failed or not parsed.glb_url:
            self._emit("error", parsed.error_message or "Generation failed.")
            return

        # 7. Download artifacts into a fresh project folder.
        self._status("Saving files to disk...")
        project = project_store.ProjectFolder.create(params.output_root, params.prompt)
        project.download(parsed.glb_url, "model.glb")
        code_text = ""
        if parsed.code_url:
            project.download(parsed.code_url, "code.py")
            code_text = project.read_text("code.py")
        if parsed.joints_url:
            try:
                project.download(parsed.joints_url, "joints.json")
            except ApiError:
                pass  # joints are optional

        # 8. Persist conversation history (best-effort; never fails generation).
        message_id = f"cad-{now_us}"
        remote_message_id = None
        if conversation_id:
            self._status("Saving to your Nova3D history...")
            try:
                user_msg, assistant_msg = history.build_messages(
                    user_message_id=f"user-{now_us}",
                    assistant_message_id=message_id,
                    prompt=params.prompt, image_data_urls=params.image_data_urls,
                    workflow_id=workflow_id, parsed=parsed,
                    model_option=params.model_option,
                )
                remote_message_id = history.persist(
                    self._client, conversation_id=conversation_id,
                    title=history.conversation_title(params.prompt),
                    user_msg=user_msg, assistant_msg=assistant_msg,
                    workflow_id=workflow_id,
                )
            except ApiError:
                # History sync is non-fatal; the asset is already on disk.
                pass

        # 9. Write meta.json (the durable pointer record).
        meta = project_store.build_meta(
            prompt=params.prompt, model_option=params.model_option,
            credits={"authorized": required}, workflow_id=workflow_id,
            conversation_id=conversation_id, message_id=remote_message_id or message_id,
            parsed=parsed, files=dict(project.files),
        )
        project.write_meta(meta)

        # 10. Hand the asset to the main thread for scene import.
        self._emit("done", {
            "project_dir": project.path,
            "slug": project.slug,
            "glb_path": project.files.get("model.glb"),
            "code_text": code_text,
            "code_path": project.files.get("code.py"),
            "joints": parsed.joints,
            "model_label": model_label,
            "workflow_id": workflow_id,
            "conversation_id": conversation_id,
        })

        # 11. UV atlases — generated on every successful generation (same as the
        #     web app's UV bundle). Best-effort: a UV failure is non-fatal because
        #     the model itself is already saved and in the scene.
        if parsed.code_artifact and not self._cancel.is_set():
            self._emit("uv_status", "Generating UV maps...")
            try:
                summary = uv_maps.generate(
                    self._client, parsed.code_artifact, project,
                    conversation_id=conversation_id, cancel_event=self._cancel,
                    on_status=lambda m: self._emit("uv_status", m),
                    base_request_id=workflow_id,
                )
                meta["uvs"] = summary
                project.write_meta(meta)
                self._emit("uv_done", summary)
            except ApiError as exc:
                self._emit("uv_status", f"UV maps skipped: {exc}")

        self._emit("finished")

    # ── pipeline helpers ─────────────────────────────────────────────────────
    def _build_payload(self, tier):
        """Build the /run/state payload — identical shape to the web client."""
        params = self._params
        payload = {
            "prompt": params.prompt,
            "code_llm_profile": constants.CODE_LLM_PROFILE,
            "code_llm_tier": tier,
        }
        # Paid generations intentionally omit any provider API key — the backend
        # resolves provider credentials server-side.
        if params.has_image:
            payload["has_reference_images"] = True
            payload["image_artifact"] = params.image_data_urls
        return payload

    def _poll_status(self, workflow_id):
        """Poll /status until terminal. Returns True to continue, False to stop.

        Handles three "not found" situations distinctly so a dead workflow can
        never be polled indefinitely:
          * 404 before the workflow is ever seen running → tolerated only during
            a short start-up grace window, then reported as "did not start".
          * 404 after the workflow WAS seen running → the backend terminated it
            without a queryable result (e.g. a hard fail node); reported as a
            generation failure after a few confirmations.
          * transient 502/503/504/timeouts → retried without counting.
        """
        deadline = time.monotonic() + constants.MAX_GENERATION_SECONDS
        start_grace_deadline = time.monotonic() + constants.START_VISIBLE_GRACE_SECONDS
        seen_alive = False
        consecutive_missing = 0
        while True:
            if self._cancel.is_set():
                self._emit("finished")
                return False
            if time.monotonic() > deadline:
                self._emit("error", "Generation timed out. Check your web history "
                                    f"before retrying. (Workflow {workflow_id})")
                return False
            # Sleep in small slices so cancel is responsive.
            self._interruptible_sleep(constants.STATUS_POLL_SECONDS)
            if self._cancel.is_set():
                self._emit("finished")
                return False
            try:
                status = self._client.status(workflow_id)
            except ApiError as exc:
                if api_client.is_missing_error(exc):
                    consecutive_missing += 1
                    if seen_alive and consecutive_missing >= constants.MISSING_AFTER_ALIVE_LIMIT:
                        self._emit("error", _aborted_message(workflow_id))
                        return False
                    if not seen_alive and time.monotonic() > start_grace_deadline:
                        self._emit("error", "The generation did not start on the "
                                            f"server. (Workflow {workflow_id})")
                        return False
                    self._status("Generating…")
                    continue
                if api_client.is_recoverable_lookup_error(exc):
                    self._status("Generating…")  # transient gateway error
                    continue
                self._emit("error", str(exc))
                return False
            seen_alive = True
            consecutive_missing = 0
            self._status(api_client.progress_label(status))
            if api_client.is_terminal(status):
                state, _node = api_client.status_snapshot(status)
                if state == "budget_exhausted":
                    self._emit("error", "Your credit budget was exhausted before "
                                        "the model completed.")
                    return False
                return True

    def _fetch_result(self, workflow_id):
        """Fetch /result, re-polling briefly on transient lookup errors.

        The workflow was just seen terminal, so a sustained 404 here means it
        was aborted without a queryable result — we stop after a few tries
        rather than polling for the full deadline.
        """
        deadline = time.monotonic() + constants.MAX_GENERATION_SECONDS
        consecutive_missing = 0
        while True:
            if self._cancel.is_set():
                self._emit("finished")
                return None
            try:
                raw = self._client.result(workflow_id)
            except ApiError as exc:
                if api_client.is_missing_error(exc):
                    consecutive_missing += 1
                    if consecutive_missing >= constants.MISSING_AFTER_ALIVE_LIMIT:
                        self._emit("error", _aborted_message(workflow_id))
                        return None
                    self._interruptible_sleep(constants.STATUS_POLL_SECONDS)
                    continue
                if time.monotonic() < deadline and api_client.is_recoverable_lookup_error(exc):
                    self._interruptible_sleep(constants.STATUS_POLL_SECONDS)
                    continue
                self._emit("error", str(exc))
                return None
            return api_client.parse_result(raw)

    def _interruptible_sleep(self, seconds):
        """Sleep that wakes early if the job is cancelled."""
        self._cancel.wait(timeout=seconds)


def _int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _readiness_message(reason):
    if reason == "generation_service_unavailable":
        return "The generation service is unavailable right now. Try again shortly."
    return "Generation is not available right now. Try again shortly."


def _aborted_message(workflow_id):
    """Shown when a workflow that was running stops returning a result.

    The backend ended the run without a queryable result (typically the model
    could not be built after automatic repairs). We cannot read the specific
    reason in this case, so the message is generic but honest and actionable.
    """
    return ("Generation failed — the model could not be built after automatic "
            f"repair attempts. Try again or pick a different model. "
            f"(Workflow {workflow_id})")
