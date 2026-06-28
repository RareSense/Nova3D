from __future__ import annotations

import asyncio
import secrets
import webbrowser
from dataclasses import dataclass
from typing import Awaitable, Callable, Optional
from urllib.parse import urlencode

from nova3d_mcp.client import Nova3DClient, Nova3DError
from nova3d_mcp.loopback import LoopbackServer
from nova3d_mcp.models import MCPStatus
from nova3d_mcp.session_store import SessionStore

LOGIN_TIMEOUT_SECONDS = 300.0


class Nova3DLoginError(Nova3DError):
    def __init__(
        self,
        message: str,
        *,
        browser_url: Optional[str] = None,
        should_check_status: bool = False,
        manual_fallback_only: bool = False,
    ) -> None:
        super().__init__(message)
        self.browser_url = browser_url
        self.should_check_status = should_check_status
        self.manual_fallback_only = manual_fallback_only


@dataclass
class LoginResult:
    token: str
    expires_at: Optional[str]
    status: MCPStatus
    connect_url: str
    port: int


@dataclass
class PendingLogin:
    connect_url: str
    port: int
    task: "asyncio.Task[LoginResult]"


class Nova3DAuthenticator:
    def __init__(
        self,
        *,
        base_url: str,
        app_url: str,
        session_store: SessionStore,
    ) -> None:
        self._base_url = base_url
        self._app_url = app_url.rstrip("/")
        self._session_store = session_store

    async def login(self) -> LoginResult:
        return await self.login_with_progress()

    async def login_with_progress(
        self,
        on_progress: Optional[Callable[[str], Awaitable[None]]] = None,
    ) -> LoginResult:
        pending = await self.begin_login(on_progress=on_progress)
        return await pending.task

    async def begin_login(
        self,
        on_progress: Optional[Callable[[str], Awaitable[None]]] = None,
    ) -> PendingLogin:
        state = secrets.token_urlsafe(32)
        loopback = LoopbackServer()
        try:
            port = await loopback.start()
        except OSError as e:
            raise Nova3DLoginError(
                "Nova3D could not start the local callback listener needed for browser sign-in. "
                "Use manual NOVA3D_TOKEN setup only if browser/loopback auth is unavailable in this environment.",
                manual_fallback_only=True,
            ) from e

        connect_url = self._build_connect_url(state=state, port=port)
        await _notify(
            on_progress,
            "Opening Nova3D sign-in in your browser.",
        )
        opened = webbrowser.open(connect_url)
        if not opened:
            await loopback.close()
            raise Nova3DLoginError(
                "Nova3D could not open your browser automatically. "
                f"Open this URL manually: {connect_url}",
                browser_url=connect_url,
            )
        await _notify(
            on_progress,
            "Complete the Nova3D sign-in flow in the browser tab that opened, then wait here for confirmation.",
        )

        task = asyncio.create_task(
            self._complete_login(
                loopback=loopback,
                state=state,
                connect_url=connect_url,
                port=port,
                on_progress=on_progress,
            )
        )
        return PendingLogin(connect_url=connect_url, port=port, task=task)

    async def _complete_login(
        self,
        *,
        loopback: LoopbackServer,
        state: str,
        connect_url: str,
        port: int,
        on_progress: Optional[Callable[[str], Awaitable[None]]] = None,
    ) -> LoginResult:

        try:
            callback = await loopback.wait_for_callback(LOGIN_TIMEOUT_SECONDS)
        except asyncio.TimeoutError as e:
            raise Nova3DLoginError(
                "Nova3D browser sign-in was opened successfully, but the local MCP callback was not confirmed yet. "
                "If you completed sign-in in the browser, call nova3d_status now. "
                "If status still shows not signed in, retry nova3d_login. "
                "Use manual NOVA3D_TOKEN setup only if browser/loopback auth is unavailable in this environment.",
                browser_url=connect_url,
                should_check_status=True,
            ) from e
        finally:
            await loopback.close()

        if callback.state != state:
            raise Nova3DLoginError(
                "Nova3D sign-in callback state mismatch. "
                "If you completed sign-in in the browser, call nova3d_status now. Otherwise retry nova3d_login.",
                browser_url=connect_url,
                should_check_status=True,
            )
        if not callback.code:
            raise Nova3DLoginError(
                "Nova3D sign-in callback completed without a session code. "
                "If the browser shows you are signed in, call nova3d_status now. Otherwise retry nova3d_login.",
                browser_url=connect_url,
                should_check_status=True,
            )

        await _notify(
            on_progress,
            "Browser sign-in completed. Finalizing your Nova3D MCP session.",
        )
        async with Nova3DClient(token=None, base_url=self._base_url) as client:
            try:
                exchange = await client.exchange_mcp_session(callback.code)
            except Nova3DError as e:
                raise Nova3DLoginError(
                    "Nova3D browser sign-in completed, but the MCP session could not be finalized. "
                    "If the browser shows you are signed in, call nova3d_status now. "
                    "Otherwise retry nova3d_login.",
                    browser_url=connect_url,
                    should_check_status=True,
                ) from e

        self._session_store.save_session(exchange.token, exchange.expires_at)

        await _notify(
            on_progress,
            "Nova3D sign-in completed. Checking credits and readiness.",
        )
        async with Nova3DClient(token=exchange.token, base_url=self._base_url) as client:
            status = await client.get_mcp_status()

        return LoginResult(
            token=exchange.token,
            expires_at=exchange.expires_at,
            status=status,
            connect_url=connect_url,
            port=port,
        )

    def _build_connect_url(self, *, state: str, port: int) -> str:
        query = urlencode({"state": state, "port": str(port)})
        return f"{self._app_url}/mcp/connect?{query}"


async def _notify(
    callback: Optional[Callable[[str], Awaitable[None]]],
    message: str,
) -> None:
    if callback is not None:
        await callback(message)
