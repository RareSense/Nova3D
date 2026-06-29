from __future__ import annotations

import asyncio
from dataclasses import dataclass
from html import escape
from typing import Dict, Optional
from urllib.parse import parse_qs, urlparse


@dataclass
class LoopbackCallback:
    code: Optional[str]
    state: Optional[str]
    raw_query: Dict[str, str]


class LoopbackServer:
    def __init__(self, *, client_name: Optional[str] = None) -> None:
        self._server: Optional[asyncio.base_events.Server] = None
        self._callback_future: asyncio.Future[LoopbackCallback] = (
            asyncio.get_running_loop().create_future()
        )
        self._port: Optional[int] = None
        self._client_name = client_name

    @property
    def port(self) -> int:
        if self._port is None:
            raise RuntimeError("Loopback server is not started.")
        return self._port

    async def start(self) -> int:
        self._server = await asyncio.start_server(
            self._handle_connection,
            host="127.0.0.1",
            port=0,
        )
        sockets = self._server.sockets or []
        if not sockets:
            raise RuntimeError("Loopback listener did not bind a socket.")
        self._port = int(sockets[0].getsockname()[1])
        return self._port

    async def wait_for_callback(self, timeout_seconds: float) -> LoopbackCallback:
        return await asyncio.wait_for(self._callback_future, timeout=timeout_seconds)

    async def close(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None

    async def _handle_connection(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        try:
            request_line = await reader.readline()
            path = "/"
            if request_line:
                parts = request_line.decode("utf-8", errors="replace").split()
                if len(parts) >= 2:
                    path = parts[1]

            while True:
                line = await reader.readline()
                if not line or line in (b"\r\n", b"\n"):
                    break

            parsed = urlparse(path)
            query_items = {
                key: values[-1]
                for key, values in parse_qs(parsed.query).items()
                if values
            }
            callback = LoopbackCallback(
                code=query_items.get("code"),
                state=query_items.get("state"),
                raw_query=query_items,
            )
            if not self._callback_future.done():
                self._callback_future.set_result(callback)

            body = _render_success_page(self._client_name)
            response = (
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: text/html; charset=utf-8\r\n"
                f"Content-Length: {len(body.encode('utf-8'))}\r\n"
                "Connection: close\r\n\r\n"
                f"{body}"
            )
            writer.write(response.encode("utf-8"))
            await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()


def _render_success_page(client_name: Optional[str]) -> str:
    destination = (
        escape(client_name.strip())
        if client_name and client_name.strip()
        else "your MCP client"
    )
    title = (
        f"Nova3D connected to {destination}"
        if destination != "your MCP client"
        else "Nova3D connected"
    )
    subtitle = (
        f"Your local Nova3D connection is ready in {destination}."
        if destination != "your MCP client"
        else "Your local Nova3D connection is ready."
    )
    return f"""<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <style>
      :root {{
        color-scheme: light;
        --cream: #fdf7ef;
        --ink: #2b2747;
        --muted: #6d6892;
        --border: #514d73;
        --panel: #ffffff;
        --panel-tint: #dff3fb;
        --accent: #f8a9c6;
        --accent-border: #dc81a6;
      }}

      * {{
        box-sizing: border-box;
      }}

      body {{
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 24px;
        background:
          radial-gradient(circle at 1px 1px, rgba(81, 77, 115, 0.14) 1px, transparent 0) 0 0 / 22px 22px,
          var(--cream);
        color: var(--ink);
        font-family: "Trebuchet MS", "Segoe UI", sans-serif;
      }}

      .card {{
        width: min(100%, 720px);
        border: 3px solid var(--border);
        border-radius: 18px;
        background: var(--panel);
        box-shadow: 0 16px 48px rgba(43, 39, 71, 0.12);
        padding: 32px 28px;
      }}

      .eyebrow {{
        display: inline-block;
        margin-bottom: 18px;
        padding: 7px 16px;
        border: 2px solid var(--border);
        border-radius: 999px;
        background: #e6f5fb;
        color: var(--ink);
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.22em;
        text-transform: uppercase;
      }}

      h1 {{
        margin: 0 0 14px;
        font-size: clamp(32px, 4vw, 54px);
        line-height: 1.05;
        letter-spacing: 0.03em;
      }}

      p {{
        margin: 0;
        font-size: 18px;
        line-height: 1.6;
        color: var(--muted);
      }}

      .panel {{
        margin-top: 22px;
        padding: 16px 18px;
        border: 2px solid #8fd4ea;
        border-radius: 14px;
        background: var(--panel-tint);
      }}

      .panel-title {{
        display: block;
        margin-bottom: 6px;
        color: var(--ink);
        font-size: 14px;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }}

      .next-step {{
        margin-top: 20px;
        padding: 18px 20px;
        border: 2px solid var(--accent-border);
        border-radius: 14px;
        background: rgba(248, 169, 198, 0.22);
      }}

      .next-step-title {{
        display: block;
        margin-bottom: 6px;
        color: var(--ink);
        font-size: 14px;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }}

      .next-step p {{
        color: var(--ink);
        font-size: 21px;
        line-height: 1.45;
      }}

      .footer {{
        margin-top: 20px;
        font-size: 15px;
      }}
    </style>
  </head>
  <body>
    <main class="card">
      <div class="eyebrow">MCP setup complete</div>
      <h1>{title}</h1>
      <p>{subtitle}</p>
      <section class="next-step">
        <span class="next-step-title">Next step</span>
        <p>You can close this tab and return to {destination} now.</p>
      </section>
      <section class="panel">
        <span class="panel-title">What happened</span>
        The Nova3D browser sign-in flow finished its local connection step on this machine.
      </section>
      <p class="footer">
        If setup does not continue automatically, check Nova3D status again from {destination}.
      </p>
    </main>
  </body>
</html>"""
