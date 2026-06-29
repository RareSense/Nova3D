# SPDX-License-Identifier: MIT
"""The end-to-end generation pipeline, run on a background worker thread.

The worker performs every blocking step (preflight, start, poll, download,
history, optional UV maps) and reports progress to the operator through a
thread-safe queue. It NEVER touches `bpy` — the only Blender-side work
(importing the GLB, creating the text datablock, hiding old collections) happens
on the main thread in `operators/generate.py` when it receives the `done` event.

Durability (so a generation is never lost):
  * The backend run is durable (Temporal); the client matches it. The moment a
    workflow starts we write a `pending` record to disk. It is removed only on a
    definite outcome we handled — success, a known failure, or explicit cancel.
  * Polling rides through transient network errors (dropped connection, DNS
    blip, 502/503/504, timeouts) for several minutes rather than aborting, so a
    momentary blip never loses a running generation (this is what makes the web
    history populate, exactly like the MCP server).
  * If the client is interrupted anyway (laptop sleep, Blender closed, a long
    outage), the pending record survives and the run is resumed later — on the
    next launch or via the Resume button — by re-attaching to the same workflow
    id with `GenerationJob.for_resume(...)`.

Event protocol (queue items are `(kind, payload)`):
    ("status",   str)      progress line update
    ("workflow", str)      the workflow id, as soon as it is known
    ("done",     dict)     model is on disk; main thread should import it now
    ("uv_status",str)      UV sub-step progress
    ("uv_done",  dict)     UV atlases written
    ("error",    str)      terminal/abandoned outcome (user-safe message)
    ("finished", None)     the job is fully complete
"""

import threading
import time

from .. import constants
from ..api import client as api_client
from ..api.errors import ApiError, AuthError
from . import history, pending, project_store, uv_maps


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
    """Runs one generation (fresh or resumed) and emits progress events."""

    def __init__(self, params, queue):
        super().__init__(daemon=True, name="Nova3DGeneration")
        self._params = params
        self._queue = queue
        self._cancel = threading.Event()
        self._client = api_client.Nova3DClient(params.api_base_url, params.api_key)
        self._conversation_id = None
        self._workflow_id = None
        self._required = 0
        self._now_us = int(time.time() * 1_000_000)
        self._resume = False  # True when re-attaching to an existing workflow

    @classmethod
    def for_resume(cls, record, *, api_base_url, api_key, queue):
        """Build a job that re-attaches to an already-started workflow."""
        params = GenerationParams(
            api_base_url=api_base_url, api_key=api_key,
            prompt=record.get("prompt", ""),
            image_data_urls=record.get("image_data_urls") or [],
            model_option=tuple(record.get("model_option") or ("", "", "", 0, "")),
            output_root=record.get("output_root"),
        )
        job = cls(params, queue)
        job._resume = True
        job._conversation_id = record.get("conversation_id")
        job._workflow_id = record.get("workflow_id")
        job._required = int(record.get("required") or 0)
        job._now_us = int(record.get("now_us") or job._now_us)
        return job

    # ── public control ───────────────────────────────────────────────────────
    def cancel(self):
        self._cancel.set()

    @property
    def cancelled(self):
        return self._cancel.is_set()

    # ── event + outcome helpers ──────────────────────────────────────────────
    def _emit(self, kind, payload=None):
        self._queue.put((kind, payload))

    def _status(self, message):
        self._emit("status", message)

    def _remove_pending(self):
        if self._workflow_id:
            try:
                pending.remove(self._params.output_root, self._workflow_id)
            except OSError:
                pass

    def _fail(self, message):
        """A definite terminal failure: record it to the conversation (so web
        history shows the failure, not an empty thread), drop the pending record
        (resuming a known failure is pointless), then surface it in Blender."""
        if self._conversation_id:
            try:
                history.persist_failure(
                    self._client, conversation_id=self._conversation_id,
                    title=history.conversation_title(self._params.prompt),
                    prompt=self._params.prompt,
                    image_data_urls=self._params.image_data_urls,
                    error_message=message, now_us=self._now_us,
                )
            except ApiError:
                pass  # history write is best-effort; never mask the real error
        self._remove_pending()
        self._emit("error", message)

    def _abandon(self, message):
        """Stop tracking but KEEP the pending record so the run can resume.

        Used when the run may still be alive on the backend (sustained network
        loss, overall timeout) — the model isn't lost, we just lost contact.
        """
        self._emit("error", message)

    def _on_cancel(self):
        """User explicitly cancelled — respect it and drop the pending record."""
        self._remove_pending()
        self._emit("finished")

    # ── thread entry point ───────────────────────────────────────────────────
    def run(self):
        try:
            if self._resume:
                self._run_resume()
            else:
                self._run_pipeline()
        except AuthError as exc:
            self._fail(str(exc))
        except ApiError as exc:
            self._fail(str(exc))
        except Exception as exc:  # noqa: BLE001 - last-resort guard for the thread
            self._fail(f"Generation failed unexpectedly: {exc}")

    # ── fresh generation ─────────────────────────────────────────────────────
    def _run_pipeline(self):
        params = self._params
        _model_id, _model_label, tier, _credits, _badge = params.model_option

        # 1. Preflight: service readiness.
        self._status("Checking the generation service...")
        readiness = self._client.readiness(constants.WORKFLOW_NAME)
        if not readiness.get("ready", False):
            self._fail(_readiness_message(readiness.get("reason")))
            return

        # 2. Preflight: credit estimate vs. wallet balance.
        self._status("Estimating credits...")
        estimate = self._client.estimate(constants.WORKFLOW_NAME, tier)
        required = int(estimate.get("authorized_budget")
                       or estimate.get("projected_max_hold") or 0)
        balance = self._client.balance()
        available = _int(balance.get("available"))
        if available is None:
            self._fail("Could not confirm your credit balance. "
                       "Open Buy Credits, refresh, and try again.")
            return
        if available < required:
            self._fail(f"This model needs {required} credits, but you have "
                       f"{available}. Use 'Buy Credits' and try again.")
            return
        self._required = required

        if self._cancel.is_set():
            self._on_cancel()
            return

        # 3. Create the conversation so this generation shows in web history.
        self._status("Creating session...")
        conversation = self._client.create_conversation(
            history.conversation_title(params.prompt))
        self._conversation_id = conversation.get("id") or conversation.get("conversation_id")

        # 4. Start the workflow (linked to the conversation).
        workflow_id = f"state-{self._now_us}"
        self._status("Starting generation...")
        payload = self._build_payload(tier)
        try:
            workflow_id = self._client.start_generation(
                constants.WORKFLOW_NAME, request_id=workflow_id, payload=payload,
                return_nodes=constants.GENERATION_RETURN_NODES,
                conversation_link=history.start_link(self._conversation_id)
                if self._conversation_id else None,
            )
        except AuthError:
            raise
        except ApiError as exc:
            # Transport/timeout error (no HTTP status) may still have started the
            # workflow — poll the id we requested. A real HTTP error (e.g. 402)
            # must surface instead of silently charging the user.
            if exc.status is not None:
                raise
        self._workflow_id = workflow_id

        # Persist the pending record NOW, before polling — so a crash, close, or
        # outage from this point on can be resumed.
        try:
            pending.save(params.output_root, pending.build_record(
                workflow_id=workflow_id, conversation_id=self._conversation_id,
                prompt=params.prompt, image_data_urls=params.image_data_urls,
                model_option=params.model_option, output_root=params.output_root,
                now_us=self._now_us, required=required))
        except OSError:
            pass  # a disk hiccup must not abort an already-running generation

        self._emit("workflow", workflow_id)
        self._complete()

    # ── resumed generation (re-attach to an existing workflow) ───────────────
    def _run_resume(self):
        if not self._workflow_id:
            self._emit("finished")
            return
        self._status("Resuming a previous generation...")
        self._emit("workflow", self._workflow_id)
        self._complete()

    # ── shared tail: poll → result → save → import → history → uv ────────────
    def _complete(self):
        params = self._params
        _id, model_label, _tier, _c, _b = params.model_option
        workflow_id = self._workflow_id

        if not self._poll_status():
            return

        self._status("Finalizing the model...")
        parsed = self._fetch_result()
        if parsed is None:
            return
        if parsed.failed or not parsed.glb_url:
            self._fail(parsed.error_message or "Generation failed.")
            return

        # Download artifacts into a fresh project folder.
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

        # Persist conversation history (best-effort; never fails the generation).
        message_id = f"cad-{self._now_us}"
        remote_message_id = None
        if self._conversation_id:
            self._status("Saving to your Nova3D history...")
            try:
                user_msg, assistant_msg = history.build_messages(
                    user_message_id=f"user-{self._now_us}",
                    assistant_message_id=message_id,
                    prompt=params.prompt, image_data_urls=params.image_data_urls,
                    workflow_id=workflow_id, parsed=parsed,
                    model_option=params.model_option,
                )
                remote_message_id = history.persist(
                    self._client, conversation_id=self._conversation_id,
                    title=history.conversation_title(params.prompt),
                    user_msg=user_msg, assistant_msg=assistant_msg,
                    workflow_id=workflow_id,
                )
            except ApiError:
                pass

        # Durable pointer record on disk.
        meta = project_store.build_meta(
            prompt=params.prompt, model_option=params.model_option,
            credits={"authorized": self._required}, workflow_id=workflow_id,
            conversation_id=self._conversation_id,
            message_id=remote_message_id or message_id, parsed=parsed,
            files=dict(project.files),
        )
        project.write_meta(meta)

        # Hand the asset to the main thread for scene import.
        self._emit("done", {
            "project_dir": project.path,
            "slug": project.slug,
            "glb_path": project.files.get("model.glb"),
            "code_text": code_text,
            "code_path": project.files.get("code.py"),
            "joints": parsed.joints,
            "model_label": model_label,
            "workflow_id": workflow_id,
            "conversation_id": self._conversation_id,
        })

        # Success — the run no longer needs to be resumable.
        self._remove_pending()

        # UV atlases — every successful generation, same as the web app's bundle.
        # Best-effort: a UV failure is non-fatal (the model is already saved).
        if parsed.code_artifact and not self._cancel.is_set():
            self._emit("uv_status", "Generating UV maps...")
            try:
                summary = uv_maps.generate(
                    self._client, parsed.code_artifact, project,
                    conversation_id=self._conversation_id, cancel_event=self._cancel,
                    on_status=lambda m: self._emit("uv_status", m),
                    base_request_id=workflow_id,
                )
                meta["uvs"] = summary
                project.write_meta(meta)
                self._emit("uv_done", summary)
            except ApiError as exc:
                self._emit("uv_status", f"UV maps skipped: {exc}")

        self._emit("finished")

    # ── helpers ──────────────────────────────────────────────────────────────
    def _build_payload(self, tier):
        """Build the /run/state payload — identical shape to the web client."""
        params = self._params
        payload = {
            "prompt": params.prompt,
            "code_llm_profile": constants.CODE_LLM_PROFILE,
            "code_llm_tier": tier,
        }
        if params.has_image:
            payload["has_reference_images"] = True
            payload["image_artifact"] = params.image_data_urls
        return payload

    def _poll_status(self):
        """Poll /status until terminal. Returns True to continue, False to stop.

        Resilience model:
          * transient transport errors (dropped connection, DNS, 502/503/504,
            timeouts) are retried for up to LOST_CONNECTION_LIMIT polls; only a
            sustained outage abandons the run (keeping it resumable).
          * 404 before the workflow is ever seen → tolerated for a short start-up
            grace window, then reported as "did not start".
          * 404 after it WAS seen running → backend ended it without a queryable
            result (e.g. a hard fail node) → reported as a failure.
        """
        workflow_id = self._workflow_id
        deadline = time.monotonic() + constants.MAX_GENERATION_SECONDS
        start_grace = time.monotonic() + constants.START_VISIBLE_GRACE_SECONDS
        seen_alive = False
        missing = 0
        transport = 0
        while True:
            if self._cancel.is_set():
                self._on_cancel()
                return False
            if time.monotonic() > deadline:
                self._abandon(_timeout_message(workflow_id))
                return False
            self._interruptible_sleep(constants.STATUS_POLL_SECONDS)
            if self._cancel.is_set():
                self._on_cancel()
                return False
            try:
                status = self._client.status(workflow_id)
            except ApiError as exc:
                if isinstance(exc, AuthError) or exc.status == 401:
                    self._fail(str(exc))
                    return False
                if api_client.is_missing_error(exc):
                    missing += 1
                    transport = 0
                    if seen_alive and missing >= constants.MISSING_AFTER_ALIVE_LIMIT:
                        self._fail(_aborted_message(workflow_id))
                        return False
                    if not seen_alive and time.monotonic() > start_grace:
                        self._fail("The generation did not start on the server. "
                                   f"(Workflow {workflow_id})")
                        return False
                    self._status("Generating…")
                    continue
                if exc.status is None or api_client.is_recoverable_lookup_error(exc):
                    transport += 1
                    missing = 0
                    if transport >= constants.LOST_CONNECTION_LIMIT:
                        self._abandon(_lost_connection_message(workflow_id))
                        return False
                    self._status("Generating… (reconnecting)")
                    continue
                self._fail(str(exc))
                return False
            seen_alive = True
            missing = 0
            transport = 0
            self._status(api_client.progress_label(status))
            if api_client.is_terminal(status):
                state, _node = api_client.status_snapshot(status)
                if state == "budget_exhausted":
                    self._fail("Your credit budget was exhausted before the model "
                               "completed.")
                    return False
                return True

    def _fetch_result(self):
        """Fetch /result with the same resilience as polling."""
        workflow_id = self._workflow_id
        missing = 0
        transport = 0
        while True:
            if self._cancel.is_set():
                self._on_cancel()
                return None
            try:
                raw = self._client.result(workflow_id)
            except ApiError as exc:
                if isinstance(exc, AuthError) or exc.status == 401:
                    self._fail(str(exc))
                    return None
                if api_client.is_missing_error(exc):
                    missing += 1
                    transport = 0
                    if missing >= constants.MISSING_AFTER_ALIVE_LIMIT:
                        self._fail(_aborted_message(workflow_id))
                        return None
                    self._interruptible_sleep(constants.STATUS_POLL_SECONDS)
                    continue
                if exc.status is None or api_client.is_recoverable_lookup_error(exc):
                    transport += 1
                    missing = 0
                    if transport >= constants.LOST_CONNECTION_LIMIT:
                        self._abandon(_lost_connection_message(workflow_id))
                        return None
                    self._interruptible_sleep(constants.STATUS_POLL_SECONDS)
                    continue
                self._fail(str(exc))
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
    """A workflow that was running stopped returning a result — the backend ended
    it without a queryable result (typically the model could not be built after
    automatic repairs). The specific reason is unreadable in this case."""
    return ("Generation failed — the model could not be built after automatic "
            f"repair attempts. Try again or pick a different model. "
            f"(Workflow {workflow_id})")


def _lost_connection_message(workflow_id):
    return ("Lost connection to Nova3D. Your model may still be generating — it "
            "will resume automatically next time, or use the Resume button. "
            f"(Workflow {workflow_id})")


def _timeout_message(workflow_id):
    return ("Generation is taking longer than expected. It may still finish — it "
            "will resume next time, or use the Resume button. "
            f"(Workflow {workflow_id})")
