# SPDX-License-Identifier: MIT
"""Minimal JSON-over-HTTPS helpers built on the Python standard library.

Blender ships its own Python without third-party packages, and asking users to
`pip install requests` into Blender is fragile. Everything here therefore uses
`urllib` + `ssl` only, so the add-on installs and runs with zero dependencies.

All functions are blocking and must be called from a worker thread, never from
Blender's main thread.
"""

import json
import ssl
import urllib.error
import urllib.request

from .errors import ApiError, AuthError, ServiceUnavailableError

# One shared, certificate-validating TLS context. We never disable verification —
# that would expose the user's API key to interception.
_SSL_CONTEXT = ssl.create_default_context()

_JSON_HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json",
}


def _decode_error_body(raw):
    """Best-effort extraction of (code, category, message) from an error body."""
    try:
        data = json.loads(raw.decode("utf-8"))
    except Exception:
        text = (raw or b"").decode("utf-8", "replace").strip()
        return None, None, (text or None)

    detail = data.get("detail") if isinstance(data, dict) else None
    if isinstance(detail, dict):
        return (detail.get("code"), detail.get("category") or detail.get("code"),
                detail.get("message") or detail.get("detail"))
    if isinstance(data, dict):
        message = data.get("message") or data.get("error") or detail
        category = data.get("error_category") or data.get("category")
        return data.get("code"), category, (message if isinstance(message, str) else None)
    if isinstance(detail, str):
        return None, None, detail
    return None, None, None


def request_json(method, url, *, headers=None, body=None, timeout=30.0):
    """Perform a JSON request and return the decoded response (or None on 204).

    Raises `AuthError` on 401 and `ApiError` on any other non-2xx status or
    transport failure. The raised message is always safe to display.
    """
    merged = dict(_JSON_HEADERS)
    if headers:
        merged.update(headers)

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(url, data=data, headers=merged, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT) as resp:
            payload = resp.read()
            if not payload:
                return None
            return json.loads(payload.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw = exc.read() if hasattr(exc, "read") else b""
        code, category, message = _decode_error_body(raw)
        status = exc.code
        if status == 401:
            raise AuthError(
                message or "Your Nova3D API key was rejected. Update it in the "
                           "add-on preferences.",
                status=status, code=code, category=category,
            ) from None
        # 5xx is the server failing, not the caller — flag it as an outage so the
        # UI can distinguish "Nova3D is down" from a bad request or key.
        if 500 <= status <= 599:
            raise ServiceUnavailableError(
                message or f"Nova3D is temporarily unavailable ({status}).",
                status=status, code=code, category=category,
            ) from None
        raise ApiError(
            message or f"Request failed ({status}).",
            status=status, code=code, category=category,
        ) from None
    except urllib.error.URLError as exc:
        raise ServiceUnavailableError(
            f"Could not reach the Nova3D service ({exc.reason}). "
            "Check your connection or the API base URL in preferences."
        ) from None
    except (TimeoutError, ssl.SSLError) as exc:
        raise ServiceUnavailableError(
            f"Network error contacting Nova3D: {exc}"
        ) from None


def download_to_file(url, dest_path, *, timeout=300.0, chunk_size=1 << 16):
    """Stream a (signed) artifact URL to *dest_path*. Returns the byte count."""
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT) as resp, \
                open(dest_path, "wb") as out:
            total = 0
            while True:
                chunk = resp.read(chunk_size)
                if not chunk:
                    break
                out.write(chunk)
                total += len(chunk)
            return total
    except (urllib.error.URLError, TimeoutError, ssl.SSLError, OSError) as exc:
        raise ApiError(f"Failed to download an artifact: {exc}") from None
