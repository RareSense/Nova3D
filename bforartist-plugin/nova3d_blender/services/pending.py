# SPDX-License-Identifier: MIT
"""Disk-backed registry of in-flight generations, so none are ever lost.

A generation runs on the backend (Temporal) durably — it keeps going whether or
not Blender is open. The client must match that: the moment a workflow starts we
write a small pointer record to ``<output_root>/.pending/<workflow_id>.json``.

The record is removed only when the run reaches a definite outcome we handled:
success (model imported), a known failure, or an explicit user cancel. It is
KEPT across anything that just interrupts the client — a network drop, a laptop
sleep, closing Blender — so the generation can be resumed later (auto on the next
launch, or via the Resume button) by re-attaching to the same workflow id.

No API key is stored here — only non-secret pointers. The key is always read
fresh from preferences at resume time.
"""

import glob
import json
import os

from . import project_store


def _dir(output_root):
    return os.path.join(project_store.expand_root(output_root), ".pending")


def record_path(output_root, workflow_id):
    return os.path.join(_dir(output_root), f"{_safe(workflow_id)}.json")


def _safe(workflow_id):
    return "".join(c if (c.isalnum() or c in "-_.") else "_" for c in str(workflow_id))


def save(output_root, record):
    """Atomically write a pending record (write-temp-then-rename)."""
    wid = record.get("workflow_id")
    if not wid:
        return
    folder = _dir(output_root)
    os.makedirs(folder, exist_ok=True)
    path = record_path(output_root, wid)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(record, fh)
    os.replace(tmp, path)


def remove(output_root, workflow_id):
    """Delete a pending record. Safe if it does not exist."""
    try:
        os.remove(record_path(output_root, workflow_id))
    except OSError:
        pass


def load_all(output_root):
    """Return all pending records, oldest first (by start time)."""
    records = []
    for path in glob.glob(os.path.join(_dir(output_root), "*.json")):
        try:
            with open(path, encoding="utf-8") as fh:
                records.append(json.load(fh))
        except Exception:
            # A corrupt/partial record should never break resume of the others.
            continue
    records.sort(key=lambda r: r.get("now_us", 0))
    return records


def count(output_root):
    try:
        return len(glob.glob(os.path.join(_dir(output_root), "*.json")))
    except OSError:
        return 0


def build_record(*, workflow_id, conversation_id, prompt, image_data_urls,
                 model_option, output_root, now_us, required):
    """Assemble the JSON-serialisable pending record."""
    return {
        "schema": 1,
        "workflow_id": workflow_id,
        "conversation_id": conversation_id,
        "prompt": prompt,
        "image_data_urls": list(image_data_urls or []),
        # (id, label, tier, credits, badge, provider). `provider` names which
        # BYOK provider was used — never the key itself; resume only polls.
        "model_option": list(model_option),
        "output_root": output_root,
        "now_us": now_us,
        "required": required,
    }
