from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

WORKFLOW_TTL_SECONDS = 86400  # 24h; well past the ~45-min max generation


def _default_store_path() -> Path:
    override = os.environ.get("NOVA3D_WORKFLOW_STORE_PATH", "").strip()
    if override:
        return Path(override).expanduser()

    xdg_state_home = os.environ.get("XDG_STATE_HOME", "").strip()
    if xdg_state_home:
        root = Path(xdg_state_home).expanduser()
    else:
        root = Path.home() / ".local" / "state"
    return root / "nova3d" / "mcp-workflows.json"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_iso(value: Any) -> Optional[datetime]:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


class WorkflowStore:
    """File-backed map of workflow_id -> per-workflow context + completion cache."""

    def __init__(self, path: Optional[Path] = None):
        self._path = path or _default_store_path()

    @property
    def path(self) -> Path:
        return self._path

    def put(
        self,
        workflow_id: str,
        *,
        operation: str,
        conversation_id: Optional[str],
        prompt: Optional[str],
        description: Optional[str],
        title: Optional[str],
        model_option_id: Optional[str],
    ) -> None:
        data = self._load_pruned()
        data["workflows"][workflow_id] = {
            "operation": operation,
            "conversation_id": conversation_id,
            "prompt": prompt,
            "description": description,
            "title": title,
            "model_option_id": model_option_id,
            "created_at": _now_iso(),
            "completed": False,
            "result_payload": None,
        }
        self._write(data)

    def get(self, workflow_id: str) -> Optional[Dict[str, Any]]:
        data = self._load_pruned()
        entry = data["workflows"].get(workflow_id)
        # Persist any pruning that happened during load.
        self._write(data)
        return entry

    def complete(self, workflow_id: str, result_payload: Dict[str, Any]) -> None:
        data = self._load_pruned()
        entry = data["workflows"].get(workflow_id)
        if entry is None:
            self._write(data)
            return
        entry["completed"] = True
        entry["result_payload"] = result_payload
        self._write(data)

    # ── internals ──────────────────────────────────────────────────────────
    def _load_pruned(self) -> Dict[str, Any]:
        data = self._load_raw()
        now = datetime.now(timezone.utc)
        kept: Dict[str, Any] = {}
        for wf_id, entry in data["workflows"].items():
            created = _parse_iso(entry.get("created_at")) if isinstance(entry, dict) else None
            if created is None:
                continue
            if (now - created).total_seconds() <= WORKFLOW_TTL_SECONDS:
                kept[wf_id] = entry
        data["workflows"] = kept
        return data

    def _load_raw(self) -> Dict[str, Any]:
        try:
            payload = json.loads(self._path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {"workflows": {}}
        except json.JSONDecodeError:
            return {"workflows": {}}
        if not isinstance(payload, dict) or not isinstance(payload.get("workflows"), dict):
            return {"workflows": {}}
        return payload

    def _write(self, data: Dict[str, Any]) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.write_text(json.dumps(data), encoding="utf-8")
        try:
            os.chmod(self._path, 0o600)
        except OSError:
            pass
