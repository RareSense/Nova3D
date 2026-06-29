# SPDX-License-Identifier: MIT
"""Browser ("Sign in with Google") worker.

Runs the loopback sign-in on a background thread and reports progress to the
operator through a thread-safe queue, exactly like `GenerationJob`. It reuses
the hosted MCP browser-login flow, so it needs no backend changes:

    open <web>/mcp/connect?state=..&port=..   (user authenticates with Google)
        -> app redirects to http://127.0.0.1:<port>/?code=..&state=..
        -> swap the code for an n3d_ token at <api>/mcp/session/exchange

The captured token is handed to the main thread (`signed_in` event), which is
the only place it is written into add-on preferences — the worker never touches
`bpy`.

Event protocol (queue items are `(kind, payload)`):
    ("status",    str)    progress line update
    ("signed_in", dict)   {"token": str, "expires_at": str|None} — store it
    ("error",     str)    user-safe failure message
    ("finished",  None)   the job is done (cancel or after signed_in)
"""

import secrets
import threading
import webbrowser
from urllib.parse import urlencode

from .. import constants
from ..api import client as api_client
from ..api.errors import ApiError
from ..api.loopback import LoopbackServer


class SignInJob(threading.Thread):
    """Drives one browser sign-in to completion."""

    def __init__(self, *, api_base_url, web_base_url, queue):
        super().__init__(daemon=True, name="Nova3DSignIn")
        self._api_base = api_base_url
        self._web_base = (web_base_url or constants.DEFAULT_WEB_BASE_URL).rstrip("/")
        self._queue = queue
        self._cancel = threading.Event()

    def cancel(self):
        self._cancel.set()

    def _emit(self, kind, payload=None):
        self._queue.put((kind, payload))

    def run(self):
        server = LoopbackServer()
        try:
            self._run(server)
        except ApiError as exc:
            self._emit("error", str(exc))
        except Exception as exc:  # noqa: BLE001 - last-resort guard for the thread
            self._emit("error", f"Sign-in failed: {exc}")
        finally:
            server.close()

    def _run(self, server):
        # CSRF guard: the callback must echo this exact value back.
        state = secrets.token_urlsafe(32)
        port = server.start()
        connect_url = (
            f"{self._web_base}{constants.MCP_CONNECT_PATH}?"
            + urlencode({
                "state": state,
                "port": port,
                # The connect page renders "Continue in <client_name>".
                "client_name": constants.CLIENT_DISPLAY_NAME,
            })
        )

        self._emit("status", "Opening your browser to sign in…")
        if not webbrowser.open(connect_url):
            self._emit("error", "Could not open a browser automatically. "
                                f"Open this URL manually:\n{connect_url}")
            return

        self._emit("status", "Waiting for you to finish signing in…")
        result = server.wait_for_callback(
            constants.SIGN_IN_TIMEOUT_SECONDS, cancel_event=self._cancel)

        if self._cancel.is_set():
            self._emit("finished")
            return
        if result is None:
            self._emit("error", "Sign-in timed out. Click Sign in to try again.")
            return

        code, returned_state = result
        if returned_state != state:
            # Mismatch means the callback didn't originate from our request.
            self._emit("error", "Sign-in security check failed. Try again.")
            return
        if not code:
            self._emit("error", "Sign-in did not return a code. Try again.")
            return

        self._emit("status", "Finalizing your session…")
        token, expires_at = api_client.exchange_session(self._api_base, code)
        self._emit("signed_in", {"token": token, "expires_at": expires_at})
        self._emit("finished")
