# SPDX-License-Identifier: MIT
"""Optional UV-atlas generation, mirroring the web client's UV bundle.

The web editor derives UV atlases from a version's *source code* (never the GLB)
via the `generate_uv_maps` workflow, producing two packings:

  * "Combined"  — everything in one atlas (atlas_mode=budget, max_atlases=1)
  * "Per-group" — one atlas per hierarchy group (atlas_mode=group)

Here we reproduce that and write the SVG atlases (+ the checker GLB) into the
project's `uvs/` folder. This step is best-effort: if the backend has no
`generate_uv_maps` workflow, or it fails, the generation as a whole still
succeeds — we simply skip the atlases.

Runs entirely on the worker thread (no `bpy`).
"""

import os
import time

from .. import constants
from ..api import client as api_client
from ..api import http
from ..api.errors import ApiError

_SETS = (
    # (label, atlas_mode, max_atlases, folder)
    ("Combined", "budget", 1, "combined"),
    ("Per-group", "group", None, "per_group"),
)


def _poll_until_terminal(client, workflow_id, cancel_event, deadline):
    """Poll a UV workflow to completion. Returns the /result body or raises."""
    while True:
        if cancel_event.is_set():
            raise ApiError("UV generation cancelled.")
        if time.monotonic() > deadline:
            raise ApiError("UV generation timed out.")
        time.sleep(constants.STATUS_POLL_SECONDS)
        try:
            status = client.status(workflow_id)
        except ApiError as exc:
            if api_client.is_recoverable_lookup_error(exc):
                continue
            raise
        if api_client.is_terminal(status):
            break
    while True:
        if cancel_event.is_set():
            raise ApiError("UV generation cancelled.")
        if time.monotonic() > deadline:
            raise ApiError("UV generation timed out.")
        try:
            return client.result(workflow_id)
        except ApiError as exc:
            if not api_client.is_recoverable_lookup_error(exc):
                raise
            time.sleep(constants.STATUS_POLL_SECONDS)


def _parse_uv_result(result_json):
    """Extract (checker_glb_url, [(group, svg_url), ...]) from a UV /result body.

    Mirrors UvMapsResult.fromResultJson in the web client.
    """
    node = result_json.get("uv_unwrap")
    payload = node[0] if isinstance(node, list) and node and isinstance(node[0], dict) else None
    if payload is None:
        payload = result_json
    data = payload.get("result") if isinstance(payload.get("result"), dict) else payload

    if data.get("ok") is not True or (data.get("status") or "").lower() == "failed":
        return None, []

    checker = data.get("checker_glb_artifact")
    checker_url = checker.get("url") if isinstance(checker, dict) else None

    atlases = []
    for entry in data.get("atlas_artifacts") or []:
        if not isinstance(entry, dict):
            continue
        svg = entry.get("svg_artifact")
        url = svg.get("url") if isinstance(svg, dict) else None
        if url:
            atlases.append((entry.get("group") or "group", url))
    return checker_url, atlases


def _run_one(client, code_artifact, atlas_mode, max_atlases, *, request_id,
             conversation_id, cancel_event, deadline):
    payload = {"code_artifact": code_artifact, "atlas_mode": atlas_mode}
    if max_atlases is not None:
        payload["max_atlases"] = max_atlases
    link = None
    if conversation_id:
        link = {
            "conversation_id": conversation_id,
            "relation_type": constants.UV_WORKFLOW_NAME,
            "link_metadata": {"operation": constants.UV_WORKFLOW_NAME,
                              "client": constants.CLIENT_NAME},
        }
    workflow_id = client.start_generation(
        constants.UV_WORKFLOW_NAME, request_id=request_id, payload=payload,
        return_nodes=("uv_unwrap",), conversation_link=link,
    )
    result_json = _poll_until_terminal(client, workflow_id, cancel_event, deadline)
    return _parse_uv_result(result_json)


def generate(client, code_artifact, project, *, conversation_id, cancel_event,
             base_request_id=None):
    """Generate both UV packings into `project/uvs/`. Returns a summary dict.

    Raises ApiError only on a hard failure of *every* set; partial success is
    returned. Callers treat any exception as "skip UVs" — never fatal.
    """
    if not (isinstance(code_artifact, dict) and
            (code_artifact.get("uri") or code_artifact.get("url"))):
        raise ApiError("No source code artifact to derive UV maps from.")

    base = base_request_id or api_client_request_id()
    deadline = time.monotonic() + constants.UV_MAX_SECONDS
    uvs_root = project.uvs_dir()
    summary = {"sets": []}
    produced_any = False
    last_error = None

    for label, mode, max_atlases, folder in _SETS:
        if cancel_event.is_set():
            break
        try:
            checker_url, atlases = _run_one(
                client, code_artifact, mode, max_atlases,
                request_id=f"{base}-uv-{folder}", conversation_id=conversation_id,
                cancel_event=cancel_event, deadline=deadline,
            )
        except ApiError as exc:
            last_error = exc
            continue
        if not checker_url and not atlases:
            continue

        set_dir = os.path.join(uvs_root, folder)
        os.makedirs(set_dir, exist_ok=True)
        written = []
        for group, url in atlases:
            name = f"atlas_{project_safe(group)}.svg"
            try:
                http.download_to_file(url, os.path.join(set_dir, name))
                written.append(name)
            except ApiError:
                continue
        if checker_url:
            try:
                http.download_to_file(checker_url, os.path.join(set_dir, "checker.glb"))
            except ApiError:
                pass
        if written or checker_url:
            produced_any = True
            summary["sets"].append({"label": label, "folder": folder,
                                    "atlas_count": len(written)})

    if not produced_any and last_error is not None:
        raise last_error
    return summary


def project_safe(name):
    """Sanitise an atlas group name for use in a filename."""
    safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in str(name or "group"))
    return safe.strip("_") or "group"


def api_client_request_id():
    """A unique base id for UV sub-workflows when none is supplied."""
    return f"state-{int(time.time() * 1_000_000)}"
