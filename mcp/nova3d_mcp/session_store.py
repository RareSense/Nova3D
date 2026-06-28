from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, Optional


def _default_session_path() -> Path:
    override = os.environ.get("NOVA3D_SESSION_PATH", "").strip()
    if override:
        return Path(override).expanduser()

    xdg_state_home = os.environ.get("XDG_STATE_HOME", "").strip()
    if xdg_state_home:
        root = Path(xdg_state_home).expanduser()
    else:
        root = Path.home() / ".local" / "state"
    return root / "nova3d" / "mcp-session.json"


class SessionStore:
    def __init__(self, path: Optional[Path] = None):
        self._path = path or _default_session_path()

    @property
    def path(self) -> Path:
        return self._path

    def load_session(self) -> Dict[str, Optional[str]]:
        payload = self._load_payload()
        token = payload.get("token")
        expires_at = payload.get("expires_at")
        return {
            "token": token.strip() if isinstance(token, str) and token.strip() else None,
            "expires_at": (
                expires_at.strip()
                if isinstance(expires_at, str) and expires_at.strip()
                else None
            ),
        }

    def load_token(self) -> Optional[str]:
        return self.load_session()["token"]

    def load_expires_at(self) -> Optional[str]:
        return self.load_session()["expires_at"]

    def save_session(self, token: str, expires_at: Optional[str] = None) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload: Dict[str, Any] = {"token": token.strip()}
        if expires_at:
            payload["expires_at"] = expires_at.strip()
        self._path.write_text(json.dumps(payload), encoding="utf-8")
        try:
            os.chmod(self._path, 0o600)
        except OSError:
            pass

    def save_token(self, token: str) -> None:
        self.save_session(token)

    def clear(self) -> None:
        try:
            self._path.unlink()
        except FileNotFoundError:
            return

    def _load_payload(self) -> Dict[str, Any]:
        try:
            payload = json.loads(self._path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except json.JSONDecodeError:
            return {}
        return payload if isinstance(payload, dict) else {}
