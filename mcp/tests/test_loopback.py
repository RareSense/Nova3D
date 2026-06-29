import asyncio

import pytest

from nova3d_mcp.loopback import LoopbackServer, _render_success_page


def test_render_success_page_uses_neutral_client_fallback():
    html = _render_success_page(None)

    assert "Nova3D connected" in html
    assert "Your local Nova3D connection is ready." in html
    assert "return to your MCP client now" in html
    assert "check Nova3D status again from your MCP client" in html


def test_render_success_page_uses_explicit_client_name():
    html = _render_success_page("Claude Code")

    assert "Nova3D connected to Claude Code" in html
    assert "Your local Nova3D connection is ready in Claude Code." in html
    assert "return to Claude Code now" in html
    assert "check Nova3D status again from Claude Code" in html


@pytest.mark.asyncio
async def test_loopback_server_captures_callback_and_serves_styled_page():
    server = LoopbackServer(client_name="Codex")

    reader = asyncio.StreamReader()
    reader.feed_data(
        (
            "GET /?code=session-123&state=state-abc HTTP/1.1\r\n"
            "Host: 127.0.0.1\r\n"
            "Connection: close\r\n\r\n"
        ).encode("utf-8")
    )
    reader.feed_eof()

    class DummyWriter:
        def __init__(self) -> None:
            self.buffer = bytearray()

        def write(self, data: bytes) -> None:
            self.buffer.extend(data)

        async def drain(self) -> None:
            return None

        def close(self) -> None:
            return None

        async def wait_closed(self) -> None:
            return None

    writer = DummyWriter()

    await server._handle_connection(reader, writer)

    callback = await server.wait_for_callback(0.2)

    response_text = writer.buffer.decode("utf-8")
    assert "HTTP/1.1 200 OK" in response_text
    assert "Nova3D connected to Codex" in response_text
    assert "Your local Nova3D connection is ready in Codex." in response_text
    assert "finished its local connection step on this machine" in response_text
    assert "return to Codex now" in response_text
    assert callback.code == "session-123"
    assert callback.state == "state-abc"
