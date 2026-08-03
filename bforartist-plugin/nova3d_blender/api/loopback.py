# SPDX-License-Identifier: MIT
"""A minimal, single-shot loopback HTTP server for browser sign-in.

The "Sign in with Google" flow opens the browser to the hosted `/mcp/connect`
page, which (after the user authenticates) redirects back to
``http://127.0.0.1:<port>/?code=...&state=...``. This server captures that one
callback and hands the values to the waiting worker thread.

Security properties (this is a localhost listener, so it is deliberately tight):
  * binds **127.0.0.1 only** (never 0.0.0.0), on an OS-assigned ephemeral port;
  * captures exactly one callback, then ignores further requests;
  * the caller validates the `state` value (CSRF guard) before trusting `code`;
  * no `bpy` import — safe to run from a worker thread.

stdlib only (`http.server` + `threading`), so it works in Blender's bundled
Python with no dependencies.
"""

import http.server
import threading
import time
from urllib.parse import parse_qs, urlparse

# A small, self-contained confirmation page shown in the user's browser.
_SUCCESS_HTML = (
    "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>"
    "<meta name='viewport' content='width=device-width, initial-scale=1'>"
    "<title>Nova3D — signed in</title>"
    "<style>body{margin:0;min-height:100vh;display:grid;place-items:center;"
    "font-family:-apple-system,Segoe UI,sans-serif;background:#0d0d0d;color:#eee}"
    ".card{max-width:420px;padding:32px;text-align:center}"
    "h1{font-size:22px;margin:0 0 10px}p{color:#aaa;line-height:1.5;margin:0}"
    "</style></head><body><div class='card'>"
    "<h1>You're signed in to Nova3D</h1>"
    "<p>You can close this tab and return to Blender.</p>"
    "</div></body></html>"
)


class _CallbackHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 - http.server API name
        query = parse_qs(urlparse(self.path).query)

        def first(name):
            values = query.get(name)
            return values[-1] if values else None

        self.server.nova3d_capture(first("code"), first("state"))  # type: ignore[attr-defined]

        body = _SUCCESS_HTML.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # silence the default stderr request logging
        pass


class LoopbackServer:
    """One-shot localhost callback receiver."""

    def __init__(self):
        self._httpd = None
        self._thread = None
        self._port = None
        self._captured = threading.Event()
        self._result = None  # (code, state); read only after `_captured` is set

    def start(self):
        """Bind 127.0.0.1 on an ephemeral port and serve in a daemon thread.

        Returns the chosen port.
        """
        self._httpd = http.server.HTTPServer(("127.0.0.1", 0), _CallbackHandler)
        # Expose the capture callback to the handler via the server instance.
        self._httpd.nova3d_capture = self._capture  # type: ignore[attr-defined]
        self._port = int(self._httpd.server_address[1])
        self._thread = threading.Thread(
            target=self._httpd.serve_forever, name="Nova3DLoopback", daemon=True)
        self._thread.start()
        return self._port

    @property
    def port(self):
        if self._port is None:
            raise RuntimeError("Loopback server is not started.")
        return self._port

    def _capture(self, code, state):
        # Runs on the server thread. Record once; setting the Event publishes the
        # write to the waiting thread (Event provides the memory barrier).
        if not self._captured.is_set():
            self._result = (code, state)
            self._captured.set()

    def wait_for_callback(self, timeout_seconds, cancel_event=None):
        """Block until the callback arrives, the timeout elapses, or cancel.

        Returns (code, state), or None on timeout/cancel. Polls in small slices
        so an external cancel is responsive.
        """
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            if self._captured.wait(0.25):
                return self._result
            if cancel_event is not None and cancel_event.is_set():
                return None
        return None

    def close(self):
        """Stop serving and release the socket. Safe to call more than once."""
        if self._httpd is not None:
            try:
                self._httpd.shutdown()
            except Exception:
                pass
            self._httpd.server_close()
            self._httpd = None
        if self._thread is not None:
            self._thread.join(timeout=2.0)
            self._thread = None
