# SPDX-License-Identifier: MIT
"""Typed client for the hosted Nova3D / GraphFlow endpoints.

Every method authenticates with the user's Nova3D API key via
`Authorization: Bearer n3d_...` — the exact scheme the MCP server uses. The key
resolves server-side to the same account as the web login, so credits and
conversation history are shared automatically.

This module also contains the pure result-parsing helpers (`parse_result`),
which mirror `CadResult` in the web client so the plugin extracts the GLB/code
artifacts the same way.
"""

from .. import constants
from . import http
from .errors import ApiError, friendly_message


class Nova3DClient:
    """Thin, stateless wrapper over the GraphFlow REST API."""

    def __init__(self, api_base_url, api_key):
        self._base = (api_base_url or constants.DEFAULT_API_BASE_URL).rstrip("/")
        self._key = (api_key or "").strip()

    # ── internals ────────────────────────────────────────────────────────────
    def _auth_headers(self):
        return {"Authorization": f"Bearer {self._key}"}

    def _url(self, path):
        return f"{self._base}{path}"

    def _get(self, path, *, timeout=constants.STATUS_HTTP_TIMEOUT):
        return http.request_json("GET", self._url(path),
                                 headers=self._auth_headers(), timeout=timeout)

    def _post(self, path, body, *, timeout=constants.STATUS_HTTP_TIMEOUT):
        return http.request_json("POST", self._url(path), headers=self._auth_headers(),
                                 body=body, timeout=timeout)

    def _patch(self, path, body, *, timeout=constants.STATUS_HTTP_TIMEOUT):
        return http.request_json("PATCH", self._url(path), headers=self._auth_headers(),
                                 body=body, timeout=timeout)

    # ── preflight ────────────────────────────────────────────────────────────
    def readiness(self, workflow_name):
        return self._get(f"/workflow/readiness/{workflow_name}") or {}

    def estimate(self, workflow_name, tier, profile=constants.CODE_LLM_PROFILE):
        body = {
            "workflow_name": workflow_name,
            "num_variations": 1,
            "pricing_context": {"code_llm_profile": profile, "code_llm_tier": tier},
        }
        return self._post("/credits/estimate", body) or {}

    def balance(self):
        return self._get("/credits/balance/me") or {}

    # ── conversations / history ──────────────────────────────────────────────
    def create_conversation(self, title, *, metadata=None):
        body = {"source": constants.CLIENT_NAME, "kind": "generation", "title": title}
        if metadata:
            body["conversation_metadata"] = metadata
        return self._post("/conversations", body) or {}

    def patch_conversation_snapshot(self, conversation_id, *, title, metadata):
        body = {"title": title, "kind": "generation", "conversation_metadata": metadata}
        return self._patch(f"/conversations/{conversation_id}", body) or {}

    def append_message(self, conversation_id, *, client_message_id, role, content_text,
                       content_json, sent_at):
        body = {
            "client_message_id": client_message_id,
            "role": role,
            "status": "completed",
            "content_text": content_text,
            "content_json": content_json,
            "sent_at": sent_at,
        }
        return self._post(f"/conversations/{conversation_id}/messages", body) or {}

    def link_workflow_to_message(self, conversation_id, *, workflow_id, message_id,
                                 operation):
        body = {
            "workflow_id": workflow_id,
            "message_id": message_id,
            "relation_type": "message_result",
            "link_metadata": {
                "operation": operation,
                "client": constants.CLIENT_NAME,
                "client_relation": "asset_version",
            },
        }
        return self._post(f"/conversations/{conversation_id}/workflow-links", body)

    # ── generation lifecycle ─────────────────────────────────────────────────
    def start_generation(self, workflow_name, *, request_id, payload, return_nodes,
                         conversation_link=None):
        body = {"payload": payload, "return_nodes": list(return_nodes)}
        if conversation_link:
            body["conversation"] = conversation_link
        path = f"/run/state/{workflow_name}?request_id={request_id}"
        resp = self._post(path, body, timeout=constants.START_HTTP_TIMEOUT) or {}
        # The backend echoes the workflow id; fall back to the requested one.
        return resp.get("workflow_id") or request_id

    def status(self, workflow_id):
        return self._get(f"/status/{workflow_id}") or {}

    def result(self, workflow_id):
        return self._get(f"/result/{workflow_id}",
                         timeout=constants.RESULT_HTTP_TIMEOUT) or {}


# ── status / result parsing (pure helpers) ───────────────────────────────────
def _as_map(value):
    return value if isinstance(value, dict) else None


def status_snapshot(status_json):
    """Return (state, current_node) from a /status body.

    `current_node` is the last visited node (the web client uses the same
    heuristic: the last key of node_visit_seq), falling back to last_exit_node.
    """
    runtime = _as_map(status_json.get("runtime")) or {}
    visit_seq = _as_map(status_json.get("node_visit_seq")) or {}
    current = None
    if visit_seq:
        # dicts preserve insertion order; the last key is the most recent node.
        current = list(visit_seq.keys())[-1]
    state = (runtime.get("state") or "").lower()
    last_exit = runtime.get("last_exit_node_id")
    return state, (current or last_exit)


def is_terminal(status_json):
    state, node = status_snapshot(status_json)
    if state in constants.TERMINAL_STATES:
        return True
    return node in constants.TERMINAL_NODES


def progress_label(status_json):
    _state, node = status_snapshot(status_json)
    return constants.NODE_PROGRESS_LABELS.get(node or "", "Generating…")


def _unwrap(payload):
    inner = _as_map(payload.get("result"))
    return inner if inner is not None else payload


def _generator_payload(result_json):
    """Pick the terminal node payload from a /result body, in priority order."""
    for key in (
        "final_validated_correction", "final_latest_valid", "sketch_to_3d_generator",
        "regenerate_3d_part", "add_3d_part", "articulate_3d_model",
        "fail_generation", "require_byok_api_key",
    ):
        node = result_json.get(key)
        if isinstance(node, list) and node and isinstance(node[0], dict):
            return node[0]
    return None


def _artifact_url(artifact):
    art = _as_map(artifact)
    if art:
        url = art.get("url")
        if isinstance(url, str) and url:
            return url
    return None


class ParsedResult:
    """Normalised view of a /result body, mirroring the web client's CadResult."""

    def __init__(self, *, glb_url=None, model_artifact=None, code_artifact=None,
                 joints_artifact=None, joints=None, failed=False, error_message=None,
                 error_category=None, operation=None):
        self.glb_url = glb_url
        self.model_artifact = model_artifact
        self.code_artifact = code_artifact
        self.joints_artifact = joints_artifact
        self.joints = joints or []
        self.failed = failed
        self.error_message = error_message
        self.error_category = error_category
        self.operation = operation

    @property
    def code_url(self):
        return _artifact_url(self.code_artifact)

    @property
    def joints_url(self):
        return _artifact_url(self.joints_artifact)


def parse_result(result_json):
    """Convert a raw /result body into a `ParsedResult`."""
    payload = _generator_payload(result_json)
    if payload is None:
        return ParsedResult(failed=True,
                            error_message="The workflow returned no usable result.")

    data = _unwrap(payload)

    glb_url = data.get("model_url") if isinstance(data.get("model_url"), str) else None
    if not glb_url:
        for key in ("model", "model_artifact", "glb_artifact"):
            glb_url = _artifact_url(data.get(key))
            if glb_url:
                break

    model_artifact = None
    for key in ("model_artifact", "model", "glb_artifact"):
        model_artifact = _as_map(data.get(key))
        if model_artifact:
            break

    code_artifact = None
    for key in ("code_artifact", "source_code_artifact", "input_code_artifact"):
        code_artifact = _as_map(data.get(key))
        if code_artifact:
            break

    joints_artifact = _as_map(data.get("joints_artifact"))
    raw_joints = data.get("joints")
    joints = [j for j in raw_joints if isinstance(j, dict)] if isinstance(raw_joints, list) else []

    failure = _as_map(data.get("failure"))
    status = (data.get("status") or "").lower()
    action = (data.get("action") or "").lower()
    has_failure = (
        status == "failed" or action == "error" or data.get("ok") is False
        or failure is not None or data.get("error_category") is not None
        or data.get("user_message") is not None
    )

    category = (failure or {}).get("category") or data.get("error_category")
    message = (
        (failure or {}).get("user_message") or (failure or {}).get("message")
        or data.get("user_message") or data.get("message")
        or (friendly_message(category) if has_failure else None)
    )

    failed = (not glb_url) and (has_failure or message is not None)
    return ParsedResult(
        glb_url=glb_url, model_artifact=model_artifact, code_artifact=code_artifact,
        joints_artifact=joints_artifact, joints=joints, failed=failed,
        error_message=message, error_category=category,
        operation=data.get("operation"),
    )


def exchange_session(api_base_url, code):
    """Swap a one-time browser sign-in code for an n3d_ token.

    Unauthenticated by design — the one-time `code` *is* the credential. Returns
    (token, expires_at). Mirrors the MCP server's `exchange_mcp_session`,
    including its tolerance for the token field name.
    """
    base = (api_base_url or constants.DEFAULT_API_BASE_URL).rstrip("/")
    resp = http.request_json(
        "POST", f"{base}{constants.SESSION_EXCHANGE_PATH}",
        body={"code": (code or "").strip()},
        timeout=constants.STATUS_HTTP_TIMEOUT,
    ) or {}
    token = None
    for key in ("token", "api_key", "n3d_token", "credential"):
        value = resp.get(key)
        if isinstance(value, str) and value.strip():
            token = value.strip()
            break
    if not token:
        raise ApiError("Sign-in did not return a Nova3D credential. Try again.")
    expires_at = resp.get("expires_at")
    return token, (str(expires_at) if expires_at is not None else None)


def is_missing_error(error):
    """True when /status or /result reports the workflow is not found (404).

    Distinct from transient gateway errors: a 404 right after start means "not
    registered yet", but a sustained 404 after the workflow was seen running
    means it terminated on the backend without leaving a queryable result.
    """
    if isinstance(error, ApiError) and error.status == 404:
        return True
    text = str(error).lower()
    return "404" in text or "not found" in text


def is_recoverable_lookup_error(error):
    """True for transient /status or /result errors worth re-polling.

    Matches the web client's `_isRecoverableWorkflowLookupError`: a freshly
    started workflow can briefly 404 or the gateway can return 502/503/504.
    Auth and budget errors are never recoverable.
    """
    if isinstance(error, ApiError):
        if error.status == 401:
            return False
        if error.status in (404, 502, 503, 504):
            return True
    text = str(error).lower()
    if "sign in" in text or "token" in text or "budget was exhausted" in text:
        return False
    return any(s in text for s in (
        "404", "not found", "unavailable", "still starting",
        "timeout", "timed out", "502", "503", "504",
    ))
