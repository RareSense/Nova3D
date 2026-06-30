"""
tests/test_server.py
────────────────────────────────────────────────────────────────
Tests for server-level startup error propagation, setup tool,
and progress callback behaviour.
────────────────────────────────────────────────────────────────
"""
import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
import nova3d_mcp.server as server_module
from nova3d_mcp.auth import Nova3DLoginError, PendingLogin
from nova3d_mcp.models import WorkflowStatus, WorkflowState


@pytest.fixture(autouse=True)
def reset_startup_error():
    """Reset _startup_error before and after every test."""
    server_module._startup_error = None
    server_module._pending_login = None
    yield
    server_module._startup_error = None
    server_module._pending_login = None


@pytest.fixture(autouse=True)
def isolate_session_store(tmp_path, monkeypatch):
    monkeypatch.setenv(
        "NOVA3D_SESSION_PATH",
        str(tmp_path / "mcp-session.json"),
    )


@pytest.fixture(autouse=True)
def allow_generation_readiness_by_default(monkeypatch):
    monkeypatch.setattr(
        server_module,
        "_require_generation_ready",
        AsyncMock(return_value=None),
    )


@pytest.mark.asyncio
async def test_generate_3d_returns_error_when_startup_failed():
    server_module._startup_error = (
        "Your Nova3D API key is invalid. "
        "Check or replace it at https://app.nova3d.xyz/api-key"
    )
    result = await server_module.generate_3d(prompt="a chair")
    assert result["failed"] is True
    assert "app.nova3d.xyz/api-key" in result["error_message"]


@pytest.mark.asyncio
async def test_regenerate_part_returns_error_when_startup_failed():
    server_module._startup_error = (
        "Your Nova3D API key is invalid. "
        "Check or replace it at https://app.nova3d.xyz/api-key"
    )
    result = await server_module.regenerate_part(
        code_artifact={},
        part_type="door",
        description="glass door",
    )
    assert result["failed"] is True
    assert "app.nova3d.xyz/api-key" in result["error_message"]


@pytest.mark.asyncio
async def test_add_part_returns_error_when_startup_failed():
    server_module._startup_error = (
        "Your Nova3D API key is invalid. "
        "Check or replace it at https://app.nova3d.xyz/api-key"
    )
    result = await server_module.add_part(
        code_artifact={},
        description="a handle",
    )
    assert result["failed"] is True
    assert "app.nova3d.xyz/api-key" in result["error_message"]


@pytest.mark.asyncio
async def test_articulate_model_returns_error_when_startup_failed():
    server_module._startup_error = (
        "Your Nova3D API key is invalid. "
        "Check or replace it at https://app.nova3d.xyz/api-key"
    )
    result = await server_module.articulate_model(
        code_artifact={},
        model_url="https://nova3d.xyz/assets/abc.glb",
        articulation_request="make door swing",
    )
    assert result["failed"] is True
    assert "app.nova3d.xyz/api-key" in result["error_message"]


@pytest.mark.asyncio
async def test_get_generation_status_returns_error_when_startup_failed():
    server_module._startup_error = "Your Nova3D API key is invalid. Check or replace it at https://app.nova3d.xyz/api-key"
    result = await server_module.get_generation_status(workflow_id="state-123")
    assert result["failed"] is True
    assert "app.nova3d.xyz/api-key" in result["error_message"]


@pytest.mark.asyncio
async def test_generate_3d_proceeds_when_no_startup_error(monkeypatch):
    """Regression guard: no startup error means the tool runs normally, not short-circuited by the flag."""
    import respx
    import httpx

    server_module._startup_error = None
    monkeypatch.setenv("NOVA3D_TOKEN", "fake-token")

    with respx.mock(base_url="https://nova3d.xyz/api", assert_all_called=False) as mock:
        mock.get("/mcp/status").mock(
            return_value=httpx.Response(
                200,
                json={
                    "authenticated": True,
                    "identity": {"user_id": "u1", "email": "user@example.com", "tenant_id": "ten_1"},
                    "mcp_session": {"established": False, "expires_at": None},
                    "credits": {"balance": 10, "reserved": 0, "available": 10, "funded": True},
                    "generation_ready": True,
                    "next_action": None,
                    "next_action_url": None,
                },
            )
        )
        mock.get("/workflow/readiness/sketch_to_3d_v2").mock(
            return_value=httpx.Response(401, json={"detail": {"code": "invalid_api_key", "message": "bad key"}})
        )
        mock.post("/conversations").mock(
            return_value=httpx.Response(201, json={"id": "conv-test"})
        )
        from nova3d_mcp.client import Nova3DAuthError
        with pytest.raises(Nova3DAuthError):
            await server_module.generate_3d(prompt="a chair")


@pytest.mark.asyncio
async def test_generate_3d_submits_and_returns_workflow_id(monkeypatch):
    """generate_3d creates a conversation, submits, stores context, returns workflow_id — no blocking."""
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_testkey")
    monkeypatch.setenv("NOVA3D_API_URL", "https://nova3d.xyz/api")
    monkeypatch.delenv("NOVA3D_APP_URL", raising=False)

    mock_client = AsyncMock()
    mock_client.create_conversation = AsyncMock(return_value="conv-xyz")
    mock_client.start_generate = AsyncMock(return_value="wf-123")
    mock_client.get_result = AsyncMock()  # must NOT be called in submit path
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    stored = {}
    fake_store = MagicMock()
    fake_store.put = lambda wf, **kw: stored.update({wf: kw})
    monkeypatch.setattr(server_module, "_get_workflow_store", lambda: fake_store)

    with patch("nova3d_mcp.server.Nova3DClient", return_value=mock_client):
        result = await server_module.generate_3d(prompt="a washing machine")

    assert result["failed"] is False
    assert result["status"] == "running"
    assert result["workflow_id"] == "wf-123"
    assert result["conversation_url"] == "https://app.nova3d.xyz/chat/conv-xyz"
    assert "parts" not in result
    assert "glb_url" not in result
    mock_client.start_generate.assert_called_once()
    mock_client.get_result.assert_not_called()
    assert stored["wf-123"]["operation"] == "generate"
    assert stored["wf-123"]["conversation_id"] == "conv-xyz"
    assert stored["wf-123"]["prompt"] == "a washing machine"
    assert stored["wf-123"]["title"] == "a washing machine"
    call_kwargs = mock_client.start_generate.call_args.kwargs
    assert call_kwargs["conversation_id"] == "conv-xyz"
    assert call_kwargs["code_llm_profile"] == "nova3d_code_generation"
    assert call_kwargs["code_llm_tier"] == "gemini_3_1_pro_google"


@pytest.mark.asyncio
async def test_generate_3d_conversation_failure_still_submits(monkeypatch):
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_testkey")
    monkeypatch.delenv("NOVA3D_APP_URL", raising=False)

    mock_client = AsyncMock()
    mock_client.create_conversation = AsyncMock(side_effect=Exception("boom"))
    mock_client.start_generate = AsyncMock(return_value="wf-789")
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    fake_store = MagicMock()
    fake_store.put = MagicMock()
    monkeypatch.setattr(server_module, "_get_workflow_store", lambda: fake_store)

    with patch("nova3d_mcp.server.Nova3DClient", return_value=mock_client):
        result = await server_module.generate_3d(prompt="a chair")

    assert result["failed"] is False
    assert result["workflow_id"] == "wf-789"
    assert "conversation_url" not in result
    call_kwargs = mock_client.start_generate.call_args.kwargs
    assert call_kwargs["conversation_id"] is None


# ── Edit tool conversation propagation tests ──────────────────────────────────

@pytest.mark.asyncio
async def test_regenerate_part_propagates_conversation_id(monkeypatch):
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_testkey")
    monkeypatch.setenv("NOVA3D_API_URL", "https://nova3d.xyz/api")

    fake_result = MagicMock()
    fake_result.failed = False
    fake_result.glb_url = "https://nova3d.xyz/assets/abc.glb"
    fake_result.parts = ["body", "door"]
    fake_result.code_artifact = {"content": "import bpy # updated"}
    fake_result.model_artifact = None
    fake_result.joints_artifact = None
    fake_result.joints = []
    fake_result.workflow_id = "wf-456"
    fake_result.api_key_source = "request"

    mock_client = AsyncMock()
    mock_client.regenerate_part = AsyncMock(return_value=fake_result)
    mock_client.append_conversation_message = AsyncMock(return_value="remote-edit")
    mock_client.link_workflow_to_message = AsyncMock(return_value=None)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("nova3d_mcp.server.Nova3DClient", return_value=mock_client):
        result = await server_module.regenerate_part(
            code_artifact={
                "content": "import bpy",
                "_nova3d_conversation_id": "conv-xyz",
                "_nova3d_prompt": "original prompt",
            },
            part_type="door",
            description="glass door with chrome frame",
        )

    assert result["failed"] is False
    assert result["conversation_url"] == "https://app.nova3d.xyz/chat/conv-xyz"
    assert result["history_persisted"] is True
    assert result["code_artifact"]["_nova3d_conversation_id"] == "conv-xyz"
    assert result["code_artifact"]["_nova3d_prompt"] == "original prompt"
    mock_client.append_conversation_message.assert_called_once()
    edit_message = mock_client.append_conversation_message.call_args.args[1]
    assert edit_message["message_type"] == "asset_version"
    assert edit_message["operation"] == "regenerate_3d_part"
    call_kwargs = mock_client.regenerate_part.call_args.kwargs
    assert call_kwargs["conversation_id"] == "conv-xyz"


@pytest.mark.asyncio
async def test_regenerate_part_no_conversation_id_in_artifact(monkeypatch):
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_testkey")
    monkeypatch.setenv("NOVA3D_API_URL", "https://nova3d.xyz/api")

    fake_result = MagicMock()
    fake_result.failed = False
    fake_result.glb_url = "https://nova3d.xyz/assets/abc.glb"
    fake_result.parts = ["body"]
    fake_result.code_artifact = {"content": "import bpy"}
    fake_result.model_artifact = None
    fake_result.joints_artifact = None
    fake_result.joints = []
    fake_result.workflow_id = "wf-456"
    fake_result.api_key_source = "request"

    mock_client = AsyncMock()
    mock_client.regenerate_part = AsyncMock(return_value=fake_result)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("nova3d_mcp.server.Nova3DClient", return_value=mock_client):
        result = await server_module.regenerate_part(
            code_artifact={"content": "import bpy"},
            part_type="door",
            description="glass door",
        )

    assert result["failed"] is False
    assert "conversation_url" not in result
    assert result["history_persisted"] is False
    assert "_nova3d_conversation_id" not in result.get("code_artifact", {})
    call_kwargs = mock_client.regenerate_part.call_args.kwargs
    assert call_kwargs.get("conversation_id") is None


@pytest.mark.asyncio
async def test_add_part_propagates_conversation_id(monkeypatch):
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_testkey")
    monkeypatch.setenv("NOVA3D_API_URL", "https://nova3d.xyz/api")

    fake_result = MagicMock()
    fake_result.failed = False
    fake_result.glb_url = "https://nova3d.xyz/assets/abc.glb"
    fake_result.parts = ["body", "handle"]
    fake_result.code_artifact = {"content": "import bpy # with handle"}
    fake_result.model_artifact = None
    fake_result.joints_artifact = None
    fake_result.joints = []
    fake_result.workflow_id = "wf-789"
    fake_result.api_key_source = "request"

    mock_client = AsyncMock()
    mock_client.add_part = AsyncMock(return_value=fake_result)
    mock_client.append_conversation_message = AsyncMock(return_value="remote-edit")
    mock_client.link_workflow_to_message = AsyncMock(return_value=None)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("nova3d_mcp.server.Nova3DClient", return_value=mock_client):
        result = await server_module.add_part(
            code_artifact={"content": "import bpy", "_nova3d_conversation_id": "conv-xyz"},
            description="a chrome handle bar",
        )

    assert result["conversation_url"] == "https://app.nova3d.xyz/chat/conv-xyz"
    assert result["code_artifact"]["_nova3d_conversation_id"] == "conv-xyz"
    assert result["history_persisted"] is True
    call_kwargs = mock_client.add_part.call_args.kwargs
    assert call_kwargs["conversation_id"] == "conv-xyz"


# ── nova3d_setup tests ────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_nova3d_setup_returns_url_and_command():
    result = await server_module.nova3d_setup()
    assert "next step is not generation yet" in result["instructions"]
    assert "Call nova3d_login from inside your MCP client" in result["instructions"]
    assert "nova3d_login" in result["instructions"]
    assert "nova3d_status" in result["instructions"]
    assert "browser tab" in result["instructions"]
    assert "claude mcp add nova3d" in result["instructions"]


@pytest.mark.asyncio
async def test_nova3d_setup_available_when_startup_error_set():
    """Setup instructions must be reachable even with no token configured."""
    server_module._startup_error = "NOVA3D_TOKEN is not set."
    result = await server_module.nova3d_setup()
    assert "nova3d_login" in result["instructions"]
    assert "next step is not generation yet" in result["instructions"]


@pytest.mark.asyncio
async def test_nova3d_login_returns_status_recovery_on_ambiguous_completion():
    loop = asyncio.get_running_loop()
    task = loop.create_future()
    task.set_exception(
        Nova3DLoginError(
            "Nova3D browser sign-in was opened successfully, but the local MCP callback was not confirmed yet.",
            browser_url="https://app.nova3d.xyz/mcp/connect?state=abc&port=5555",
            should_check_status=True,
        )
    )
    mock_auth = MagicMock()
    mock_auth.begin_login = AsyncMock(
        return_value=PendingLogin(
            connect_url="https://app.nova3d.xyz/mcp/connect?state=abc&port=5555",
            port=5555,
            task=task,
        )
    )

    with patch("nova3d_mcp.server.Nova3DAuthenticator", return_value=mock_auth):
        result = await server_module.nova3d_login()

    assert result["failed"] is True
    assert result["browser_url"].startswith("https://app.nova3d.xyz/mcp/connect")
    assert result["suggested_next_step"] == "call nova3d_status"
    assert "retry nova3d_login" in result["recovery_instructions"]
    assert "manual_fallback_available" not in result


@pytest.mark.asyncio
async def test_nova3d_login_marks_manual_fallback_only_for_loopback_unavailable():
    mock_auth = MagicMock()
    mock_auth.begin_login = AsyncMock(
        side_effect=Nova3DLoginError(
            "Nova3D could not start the local callback listener needed for browser sign-in.",
            manual_fallback_only=True,
        )
    )

    with patch("nova3d_mcp.server.Nova3DAuthenticator", return_value=mock_auth):
        result = await server_module.nova3d_login()

    assert result["failed"] is True
    assert result["manual_fallback_available"] is True


@pytest.mark.asyncio
async def test_nova3d_login_returns_pending_payload_when_background_auth_in_progress():
    loop = asyncio.get_running_loop()
    task = loop.create_future()
    mock_auth = MagicMock()
    mock_auth.begin_login = AsyncMock(
        return_value=PendingLogin(
            connect_url="https://app.nova3d.xyz/mcp/connect?state=abc&port=5555",
            port=5555,
            task=task,
        )
    )

    with patch("nova3d_mcp.server.Nova3DAuthenticator", return_value=mock_auth):
        result = await server_module.nova3d_login()

    assert result["login_started"] is True
    assert result["login_pending_confirmation"] is True
    assert result["suggested_next_step"] == "call nova3d_status"
    assert result["browser_url"].startswith("https://app.nova3d.xyz/mcp/connect")
    task.cancel()


@pytest.mark.asyncio
async def test_nova3d_status_reflects_pending_login():
    loop = asyncio.get_running_loop()
    task = loop.create_future()
    server_module._pending_login = server_module.PendingLoginState(
        connect_url="https://app.nova3d.xyz/mcp/connect?state=abc&port=5555",
        port=5555,
        task=task,
    )

    status = MagicMock()
    status.authenticated = False
    status.generation_ready = False
    status.next_action = "sign_in"
    status.next_action_url = "https://nova3d.xyz/mcp/connect"
    status.user_message = "Sign in to Nova3D to continue."
    status.identity = None
    status.credits = None
    status.mcp_session = MagicMock()
    status.mcp_session.model_dump.return_value = {"established": False, "expires_at": None}

    with patch("nova3d_mcp.server._get_mcp_status", AsyncMock(return_value=status)):
        result = await server_module.nova3d_status()

    assert result["login_pending_confirmation"] is True
    assert result["browser_url"].startswith("https://app.nova3d.xyz/mcp/connect")
    assert result["suggested_next_step"] == "call nova3d_status"
    task.cancel()


@pytest.mark.asyncio
async def test_nova3d_status_returns_backend_status_payload():
    status = MagicMock()
    status.authenticated = True
    status.generation_ready = False
    status.next_action = "purchase_credits"
    status.next_action_url = "https://nova3d.xyz/mcp/no-credits"
    status.user_message = "Buy credits before generating."
    status.identity = MagicMock()
    status.identity.model_dump.return_value = {"email": "user@example.com"}
    status.credits = MagicMock()
    status.credits.model_dump.return_value = {"available": 0, "funded": False}
    status.mcp_session = MagicMock()
    status.mcp_session.model_dump.return_value = {"established": True, "expires_at": "2026-09-10T14:32:00Z"}

    with patch("nova3d_mcp.server._get_mcp_status", AsyncMock(return_value=status)):
        result = await server_module.nova3d_status()

    assert result["authenticated"] is True
    assert result["next_action"] == "purchase_credits"
    assert result["next_action_url"] == "https://nova3d.xyz/mcp/no-credits"
    assert result["identity"]["email"] == "user@example.com"


@pytest.mark.asyncio
async def test_nova3d_logout_clears_local_session(monkeypatch, tmp_path):
    monkeypatch.setenv("NOVA3D_SESSION_PATH", str(tmp_path / "session.json"))
    monkeypatch.delenv("NOVA3D_TOKEN", raising=False)

    store = server_module._get_session_store()
    store.save_token("n3d_test_session")

    result = await server_module.nova3d_logout()

    assert result["logged_out"] is True
    assert result["cleared_local_session"] is True
    assert store.load_token() is None


@pytest.mark.asyncio
async def test_nova3d_status_includes_stored_session_hint(monkeypatch, tmp_path):
    monkeypatch.setenv("NOVA3D_SESSION_PATH", str(tmp_path / "session.json"))
    store = server_module._get_session_store()
    store.save_session("n3d_test_session", "2026-06-13T12:00:00Z")

    status = MagicMock()
    status.authenticated = True
    status.generation_ready = True
    status.next_action = None
    status.next_action_url = None
    status.user_message = "Nova3D is ready."
    status.identity = None
    status.credits = None
    status.mcp_session = MagicMock()
    status.mcp_session.model_dump.return_value = {"established": True, "expires_at": "2026-06-13T12:00:00Z"}

    with patch("nova3d_mcp.server._get_mcp_status", AsyncMock(return_value=status)):
        result = await server_module.nova3d_status()

    assert result["stored_session_expires_at"] == "2026-06-13T12:00:00Z"
    assert "session_reauth_recommended" in result


def test_session_store_round_trips_expires_at(tmp_path):
    from nova3d_mcp.session_store import SessionStore

    store = SessionStore(tmp_path / "session.json")
    store.save_session("n3d_test_session", "2026-09-10T14:32:00Z")

    assert store.load_token() == "n3d_test_session"
    assert store.load_expires_at() == "2026-09-10T14:32:00Z"


@pytest.mark.asyncio
async def test_generate_3d_blocks_when_purchase_required():
    with patch(
        "nova3d_mcp.server._require_generation_ready",
        AsyncMock(
            return_value={
                "failed": True,
                "error_message": "Your Nova3D account is connected, but you need credits before generating.",
                "next_action": "purchase_credits",
                "next_action_url": "https://nova3d.xyz/mcp/no-credits",
            }
        ),
    ):
        result = await server_module.generate_3d(prompt="a chair")

    assert result["failed"] is True
    assert result["next_action"] == "purchase_credits"


@pytest.mark.asyncio
async def test_validate_startup_without_any_token_does_not_set_error(monkeypatch, tmp_path):
    monkeypatch.delenv("NOVA3D_TOKEN", raising=False)
    monkeypatch.setenv("NOVA3D_SESSION_PATH", str(tmp_path / "missing.json"))
    server_module._startup_error = "old"

    await server_module._validate_startup()

    assert server_module._startup_error is None


# ── Progress callback tests ───────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_progress_callback_reports_new_node():
    ctx = MagicMock()
    ctx.report_progress = AsyncMock()

    callback = server_module._make_progress_callback(ctx)
    status = WorkflowStatus(
        workflow_id="state-123",
        state=WorkflowState.RUNNING,
        last_exit_node="blender_code_generator",
    )
    await callback(status)

    ctx.report_progress.assert_called_once_with(
        progress=1, total=None, message="Completed: blender_code_generator"
    )


@pytest.mark.asyncio
async def test_progress_callback_deduplicates_same_node():
    ctx = MagicMock()
    ctx.report_progress = AsyncMock()

    callback = server_module._make_progress_callback(ctx)
    status = WorkflowStatus(
        workflow_id="state-123",
        state=WorkflowState.RUNNING,
        last_exit_node="blender_code_generator",
    )
    await callback(status)
    await callback(status)  # same node — should not fire again

    ctx.report_progress.assert_called_once()


@pytest.mark.asyncio
async def test_progress_callback_reports_each_new_node():
    ctx = MagicMock()
    ctx.report_progress = AsyncMock()

    callback = server_module._make_progress_callback(ctx)
    for node in ["blender_code_generator", "mesh_validator", "glb_exporter"]:
        await callback(WorkflowStatus(
            workflow_id="state-123",
            state=WorkflowState.RUNNING,
            last_exit_node=node,
        ))

    assert ctx.report_progress.call_count == 3
    messages = [call.kwargs["message"] for call in ctx.report_progress.call_args_list]
    assert messages == [
        "Completed: blender_code_generator",
        "Completed: mesh_validator",
        "Completed: glb_exporter",
    ]


@pytest.mark.asyncio
async def test_progress_callback_no_ctx_does_not_raise():
    """Regression guard: ctx=None (direct test calls) must not raise."""
    callback = server_module._make_progress_callback(None)
    status = WorkflowStatus(
        workflow_id="state-123",
        state=WorkflowState.RUNNING,
        last_exit_node="blender_code_generator",
    )
    await callback(status)  # should not raise


@pytest.mark.asyncio
async def test_progress_callback_skips_status_with_no_node():
    ctx = MagicMock()
    ctx.report_progress = AsyncMock()

    callback = server_module._make_progress_callback(ctx)
    status = WorkflowStatus(
        workflow_id="state-123",
        state=WorkflowState.RUNNING,
    )
    await callback(status)  # no node — nothing to report

    ctx.report_progress.assert_not_called()


@pytest.mark.asyncio
async def test_generate_3d_invalid_model():
    """Passing an unknown model name returns a helpful failed response immediately."""
    result = await server_module.generate_3d(
        prompt="a chair",
        model="bad-model",
    )
    assert result["failed"] is True
    assert "bad-model" in result["error_message"]
    assert "gemini" in result["error_message"]


@pytest.mark.asyncio
async def test_articulate_model_with_model_artifact(monkeypatch):
    """articulate_model accepts model_artifact in place of model_url."""
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_testkey")
    monkeypatch.setenv("NOVA3D_API_URL", "https://nova3d.xyz/api")

    fake_result = MagicMock()
    fake_result.failed = False
    fake_result.glb_url = "https://nova3d.xyz/assets/articulated.glb"
    fake_result.joints = [{"name": "door_hinge"}]
    fake_result.joint_count = 1
    fake_result.code_artifact = {"content": "import bpy"}
    fake_result.model_artifact = None
    fake_result.joints_artifact = None
    fake_result.workflow_id = "wf-art"
    fake_result.api_key_source = None

    mock_client = AsyncMock()
    mock_client.articulate_model = AsyncMock(return_value=fake_result)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    artifact = {"url": "https://nova3d.xyz/assets/abc.glb", "id": "art-123"}

    with patch("nova3d_mcp.server.Nova3DClient", return_value=mock_client):
        result = await server_module.articulate_model(
            code_artifact={"content": "import bpy"},
            articulation_request="make door swing",
            model_artifact=artifact,
        )

    assert result["failed"] is False
    call_kwargs = mock_client.articulate_model.call_args.kwargs
    assert call_kwargs["model_artifact"] == artifact
    assert call_kwargs["model_url"] is None


@pytest.mark.asyncio
async def test_articulate_model_neither_url_nor_artifact():
    """articulate_model without model_url or model_artifact returns a clear error."""
    result = await server_module.articulate_model(
        code_artifact={"content": "import bpy"},
        articulation_request="make door swing",
    )
    assert result["failed"] is True
    assert "model_url" in result["error_message"] or "model_artifact" in result["error_message"]


@pytest.mark.asyncio
async def test_finish_workflow_generate_builds_completed_payload(monkeypatch):
    """_finish_workflow embeds conversation id, persists, caches, and returns the result."""
    from unittest.mock import AsyncMock, MagicMock

    fake_result = MagicMock()
    fake_result.failed = False
    fake_result.glb_url = "https://nova3d.xyz/assets/abc.glb"
    fake_result.joint_count = 0
    fake_result.joints = []
    fake_result.code_artifact = {"url": "https://x/code.py"}
    fake_result.model_artifact = {"url": "https://x/model.glb"}
    fake_result.joints_artifact = None
    fake_result.workflow_id = "wf-123"
    fake_result.api_key_source = "request"

    mock_client = AsyncMock()
    mock_client.get_result = AsyncMock(return_value=fake_result)
    mock_client.update_conversation_snapshot = AsyncMock(return_value=None)
    mock_client.append_conversation_message = AsyncMock(side_effect=["m1", "m2"])
    mock_client.link_workflow_to_message = AsyncMock(return_value=None)

    captured_complete = {}
    fake_store = MagicMock()
    fake_store.complete = lambda wf, payload: captured_complete.update({wf: payload})
    monkeypatch.setattr(server_module, "_get_workflow_store", lambda: fake_store)
    monkeypatch.delenv("NOVA3D_APP_URL", raising=False)

    entry = {
        "operation": "generate",
        "conversation_id": "conv-xyz",
        "prompt": "a washing machine",
        "description": None,
        "title": "a washing machine",
        "model_option_id": "opt-gemini",
        "completed": False,
        "result_payload": None,
    }

    payload = await server_module._finish_workflow(mock_client, "wf-123", entry)

    assert payload["failed"] is False
    assert payload["status"] == "completed"
    assert payload["is_terminal"] is True
    assert payload["glb_url"] == "https://nova3d.xyz/assets/abc.glb"
    assert payload["code_artifact"]["_nova3d_conversation_id"] == "conv-xyz"
    assert payload["code_artifact"]["_nova3d_prompt"] == "a washing machine"
    assert payload["conversation_url"] == "https://app.nova3d.xyz/chat/conv-xyz"
    assert "parts" not in payload
    assert captured_complete["wf-123"] is payload


@pytest.mark.asyncio
async def test_finish_workflow_failed_result_returns_error(monkeypatch):
    from unittest.mock import AsyncMock, MagicMock

    fake_result = MagicMock()
    fake_result.failed = True
    fake_result.error_message = "Generation failed."
    fake_result.error_category = "blender_generation_failed"
    fake_result.retryable = False

    mock_client = AsyncMock()
    mock_client.get_result = AsyncMock(return_value=fake_result)

    completed_calls = []
    fake_store = MagicMock()
    fake_store.complete = lambda wf, payload: completed_calls.append(wf)
    monkeypatch.setattr(server_module, "_get_workflow_store", lambda: fake_store)

    entry = {
        "operation": "generate",
        "conversation_id": "conv-xyz",
        "prompt": "a chair",
        "description": None,
        "title": "a chair",
        "model_option_id": "opt-gemini",
        "completed": False,
        "result_payload": None,
    }

    payload = await server_module._finish_workflow(mock_client, "wf-err", entry)
    assert payload["failed"] is True
    assert payload["error_message"] == "Generation failed."
    assert payload["is_terminal"] is True
    assert payload["status"] == "failed"
    assert completed_calls == []  # failures are not cached
