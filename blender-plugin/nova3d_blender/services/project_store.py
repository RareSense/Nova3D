# SPDX-License-Identifier: MIT
"""Per-generation project folder on disk: the durable, user-owned record.

Layout (one folder per generation, never overwritten):

    <root>/<timestamp>_<slug>/
        model.glb         exported asset
        code.py           the Blender program that built it (re-runnable)
        joints.json        articulation rig (only if the asset has joints)
        uvs/              UV atlases (only if UV generation is enabled/succeeds)
        meta.json         pointers: workflow_id, conversation_id, message_id,
                          code_artifact, prompt, model, credits, joints, ...

`meta.json` is the local mirror of the same pointers the backend stores, so an
asset stays inspectable and re-generatable even offline.
"""

import json
import os
import re
import time

from .. import constants
from ..api import http

_SLUG_RE = re.compile(r"[^a-z0-9]+")


def slugify(text, *, fallback="model", max_len=40):
    """Filesystem-safe, lowercase slug from a prompt."""
    base = _SLUG_RE.sub("_", (text or "").strip().lower()).strip("_")
    if not base:
        return fallback
    return base[:max_len].strip("_") or fallback


def expand_root(root):
    """Resolve the configured output root (handles ~ and Blender // prefixes)."""
    raw = (root or "").strip() or "~/Nova3D"
    if raw.startswith("//"):
        # Blender-relative path; only meaningful with a saved .blend, but expand
        # defensively against the current working directory otherwise.
        raw = os.path.abspath(raw[2:])
    return os.path.abspath(os.path.expanduser(raw))


class ProjectFolder:
    """A created-on-disk generation folder plus helpers to populate it."""

    def __init__(self, path, slug):
        self.path = path
        self.slug = slug
        self.files = {}  # logical name -> absolute path actually written

    @classmethod
    def create(cls, root, prompt):
        slug = slugify(prompt)
        stamp = time.strftime("%Y%m%d_%H%M%S")
        base = expand_root(root)
        os.makedirs(base, exist_ok=True)
        # Guarantee uniqueness even within the same second.
        name = f"{stamp}_{slug}"
        path = os.path.join(base, name)
        suffix = 1
        while os.path.exists(path):
            path = os.path.join(base, f"{name}_{suffix}")
            suffix += 1
        os.makedirs(path)
        return cls(path, slug)

    def download(self, url, filename, *, timeout=constants.RESULT_HTTP_TIMEOUT):
        """Download a (signed) artifact URL into the folder. Returns the path."""
        dest = os.path.join(self.path, filename)
        http.download_to_file(url, dest, timeout=timeout)
        self.files[filename] = dest
        return dest

    def uvs_dir(self):
        path = os.path.join(self.path, "uvs")
        os.makedirs(path, exist_ok=True)
        return path

    def read_text(self, filename):
        path = os.path.join(self.path, filename)
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read()

    def write_meta(self, meta):
        path = os.path.join(self.path, "meta.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(meta, fh, indent=2, sort_keys=False)
        self.files["meta.json"] = path
        return path


def build_meta(*, prompt, model_option, credits, workflow_id, conversation_id,
               message_id, parsed, files, uv_summary=None):
    """Assemble the meta.json pointer record."""
    option_id, label, tier, display_credits, _badge = model_option
    return {
        "schema_version": 1,
        "client": constants.CLIENT_NAME,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z") or time.strftime("%Y-%m-%dT%H:%M:%S"),
        "prompt": prompt,
        "model": {
            "option_id": option_id,
            "label": label,
            "code_llm_tier": tier,
            "code_llm_profile": constants.CODE_LLM_PROFILE,
        },
        "credits": {
            "authorized": credits.get("authorized") if credits else None,
            "estimated_display": display_credits,
        },
        "workflow": {
            "name": constants.WORKFLOW_NAME,
            "workflow_id": workflow_id,
        },
        "conversation_id": conversation_id,
        "message_id": message_id,
        "model_url": parsed.glb_url,
        "code_artifact": parsed.code_artifact,
        "model_artifact": parsed.model_artifact,
        "joints_artifact": parsed.joints_artifact,
        "joints": parsed.joints,
        "files": files,
        "uvs": uv_summary,
    }
