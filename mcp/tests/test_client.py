"""
tests/test_client.py
────────────────────────────────────────────────────────────────
Unit tests for Nova3DClient.
Uses respx to mock HTTP without hitting the real API.
────────────────────────────────────────────────────────────────
"""
import json
import pytest
import respx
import httpx
from nova3d_mcp.client import _parse_auth_error
from nova3d_mcp.server import _validate_startup

from nova3d_mcp.client import Nova3DClient, Nova3DError, Nova3DCreditsError, Nova3DAuthError
from nova3d_mcp.models import GenerationResult, WorkflowState


FAKE_TOKEN = "test-jwt-token"
BASE_URL = "https://nova3d.xyz/api"
WORKFLOW_ID = "state-123456789"


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def mock_api():
    with respx.mock(base_url=BASE_URL, assert_all_called=False) as mock:
        yield mock


@pytest.fixture(autouse=True)
def isolate_session_store(tmp_path, monkeypatch):
    monkeypatch.setenv(
        "NOVA3D_SESSION_PATH",
        str(tmp_path / "mcp-session.json"),
    )


def _readiness_ok():
    return {"ready": True, "reason": None, "projected_cost": 10, "authorized_budget": 12}


def _start_ok():
    return {
        "workflow_id": WORKFLOW_ID,
        "status_url": f"/status/{WORKFLOW_ID}",
        "result_url": f"/result/{WORKFLOW_ID}",
        "projected_cost": 10,
        "authorized_budget": 12,
    }


def _status_running():
    return {
        "runtime": {"state": "running", "last_exit_node_id": None},
        "node_visit_seq": {"sketch_to_3d_generator": 1},
    }


def _status_completed():
    return {
        "runtime": {"state": "completed", "last_exit_node_id": "final_latest_valid"},
        "node_visit_seq": {"final_latest_valid": 1},
    }


def _result_ok():
    return {
        "final_latest_valid": [
            {
                "status": "completed",
                "ok": True,
                "glb_artifact": {"url": "https://nova3d.xyz/assets/abc123.glb"},
                "model_artifact": {"url": "https://nova3d.xyz/assets/abc123.glb"},
                "code_artifact": {"content": "import bpy\n# generated code"},
                "joints": [{"name": "door_hinge", "type": "revolute", "mesh": "door"}],
                "joint_count": 1,
                "operation": "initial_generation",
            }
        ]
    }


def _result_corrected_ok():
    return {
        "final_validated_correction": [
            {
                "status": "completed",
                "ok": True,
                "glb_artifact": {"url": "https://nova3d.xyz/assets/corrected.glb"},
                "code_artifact": {"content": "import bpy\n# corrected generated code"},
            }
        ]
    }


def _mcp_status_ready():
    return {
        "authenticated": True,
        "identity": {
            "user_id": "user-123",
            "email": "user@example.com",
            "tenant_id": "ten_123",
        },
        "mcp_session": {
            "established": True,
            "expires_at": "2026-09-10T14:32:00Z",
        },
        "credits": {
            "balance": 350,
            "reserved": 50,
            "available": 300,
            "funded": True,
        },
        "generation_ready": True,
        "next_action": None,
        "next_action_url": None,
    }


# ── Tests ─────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_generate_success(mock_api):
    mock_api.get("/workflow/readiness/sketch_to_3d_v2").mock(
        return_value=httpx.Response(200, json=_readiness_ok())
    )
    mock_api.post("/run/state/sketch_to_3d_v2").mock(
        return_value=httpx.Response(202, json=_start_ok())
    )
    # First status poll returns running, second returns completed
    mock_api.get(f"/status/{WORKFLOW_ID}").mock(
        side_effect=[
            httpx.Response(200, json=_status_running()),
            httpx.Response(200, json=_status_completed()),
        ]
    )
    mock_api.get(f"/result/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_result_ok())
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        # Patch sleep to avoid actual waiting in tests
        import nova3d_mcp.client as client_module
        original_sleep = client_module.asyncio.sleep
        client_module.asyncio.sleep = lambda _: original_sleep(0)

        result = await client.generate(
            prompt="a toaster with removable tray",
            code_llm_profile="nova3d_code_generation",
            code_llm_tier="gemini_3_1_pro_google",
        )

        client_module.asyncio.sleep = original_sleep

    assert result.failed is False
    assert result.glb_url == "https://nova3d.xyz/assets/abc123.glb"
    assert result.joint_count == 1
    assert result.joints[0]["name"] == "door_hinge"
    assert result.workflow_id == WORKFLOW_ID


@pytest.mark.asyncio
async def test_generate_not_ready(mock_api):
    mock_api.get("/workflow/readiness/sketch_to_3d_v2").mock(
        return_value=httpx.Response(200, json={
            "ready": False,
            "reason": "generation_service_unavailable",
        })
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        with pytest.raises(Nova3DError, match="unavailable"):
            await client.generate(
                prompt="a robot",
                code_llm_profile="nova3d_code_generation",
                code_llm_tier="gemini_3_1_pro_google",
            )


@pytest.mark.asyncio
async def test_generate_credits_error(mock_api):
    mock_api.get("/workflow/readiness/sketch_to_3d_v2").mock(
        return_value=httpx.Response(200, json=_readiness_ok())
    )
    mock_api.post("/run/state/sketch_to_3d_v2").mock(
        return_value=httpx.Response(402, json={
            "code": "credits_or_user_key_required",
            "message": "Add credits or provide your own provider API key to generate.",
        })
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        with pytest.raises(Nova3DCreditsError):
            await client.generate(
                prompt="a robot",
                code_llm_profile="nova3d_code_generation",
                code_llm_tier="gemini_3_1_pro_google",
            )


@pytest.mark.asyncio
async def test_result_parsing_glb_url():
    result = GenerationResult.from_api(_result_ok(), WORKFLOW_ID)
    assert result.glb_url == "https://nova3d.xyz/assets/abc123.glb"
    assert result.joint_count == 1
    assert result.failed is False


@pytest.mark.asyncio
async def test_result_parsing_failure():
    data = {
        "fail_generation": [
            {
                "status": "failed",
                "error_category": "blender_generation_failed",
                "user_message": "The script could not produce a valid model.",
            }
        ]
    }
    result = GenerationResult.from_api(data, WORKFLOW_ID)
    assert result.failed is True
    assert result.glb_url is None
    assert "model" in result.error_message.lower()


def test_workflow_state_parse():
    assert WorkflowState.parse("completed").is_terminal is True
    assert WorkflowState.parse("succeeded").is_terminal is True
    assert WorkflowState.parse("running").is_terminal is False
    assert WorkflowState.parse("pending").is_terminal is False
    assert WorkflowState.parse("budget_exhausted").is_terminal is True
    assert WorkflowState.parse(None) == WorkflowState.UNKNOWN


def test_recoverable_errors():
    from nova3d_mcp.client import _is_recoverable
    assert _is_recoverable("workflow not found (404)") is True
    assert _is_recoverable("request failed (502)") is True
    assert _is_recoverable("still starting") is True
    assert _is_recoverable("sign in again") is False
    assert _is_recoverable("budget was exhausted") is False
    assert _is_recoverable("invalid api key") is False



def test_parse_auth_error_revoked():
    resp = httpx.Response(401, json={
        "detail": {"code": "api_key_revoked", "message": "Key revoked."}
    })
    code, message = _parse_auth_error(resp)
    assert code == "api_key_revoked"
    assert "revoked" in message.lower()
    assert "app.nova3d.xyz/api-key" in message


def test_parse_auth_error_invalid_key():
    resp = httpx.Response(401, json={
        "detail": {"code": "invalid_api_key", "message": "Bad key."}
    })
    code, message = _parse_auth_error(resp)
    assert code == "invalid_api_key"
    assert "invalid" in message.lower()
    assert "app.nova3d.xyz/api-key" in message


def test_parse_auth_error_detail_string():
    resp = httpx.Response(401, json={"detail": "Not authenticated"})
    code, message = _parse_auth_error(resp)
    assert code is None
    assert message == "Not authenticated"


def test_parse_auth_error_no_json():
    resp = httpx.Response(401, content=b"Unauthorized")
    code, message = _parse_auth_error(resp)
    assert code is None
    assert "app.nova3d.xyz/api-key" in message


@pytest.mark.asyncio
async def test_generate_raises_auth_error_with_code(mock_api):
    mock_api.get("/workflow/readiness/sketch_to_3d_v2").mock(
        return_value=httpx.Response(200, json=_readiness_ok())
    )
    mock_api.post("/run/state/sketch_to_3d_v2").mock(
        return_value=httpx.Response(401, json={
            "detail": {"code": "api_key_revoked", "message": "Revoked."}
        })
    )
    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        with pytest.raises(Nova3DAuthError, match="revoked"):
            await client.generate(
                prompt="a robot",
                code_llm_profile="nova3d_code_generation",
                code_llm_tier="gemini_3_1_pro_google",
            )


@pytest.mark.asyncio
async def test_get_me_success(mock_api):
    mock_api.get("/me").mock(
        return_value=httpx.Response(200, json={
            "user_id": "b333345d-a36c-487e-9096-5f7fd9a2901b",
            "email": "hassan@raresense.so",
            "available_credits": 1000,
            "tenant_id": "ten_e06a051bdb1f43b7b9d5bfaea1e07bf0",
        })
    )
    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        me = await client.get_me()
    assert me["email"] == "hassan@raresense.so"
    assert me["available_credits"] == 1000


@pytest.mark.asyncio
async def test_get_me_invalid_key(mock_api):
    mock_api.get("/me").mock(
        return_value=httpx.Response(401, json={
            "detail": {"code": "invalid_api_key", "message": "Bad key."}
        })
    )
    async with Nova3DClient(token="n3d_bad", base_url=BASE_URL) as client:
        with pytest.raises(Nova3DAuthError, match="invalid"):
            await client.get_me()


@pytest.mark.asyncio
async def test_get_mcp_status_success(mock_api):
    mock_api.get("/mcp/status").mock(
        return_value=httpx.Response(200, json=_mcp_status_ready())
    )

    async with Nova3DClient(token=None, base_url=BASE_URL) as client:
        status = await client.get_mcp_status()

    assert status.authenticated is True
    assert status.generation_ready is True
    assert status.next_action is None
    assert status.identity.email == "user@example.com"
    assert status.credits.available == 300


@pytest.mark.asyncio
async def test_exchange_mcp_session_code_success(mock_api):
    mock_api.post("/mcp/session/exchange").mock(
        return_value=httpx.Response(200, json={"token": "n3d_test_session", "expires_at": "2026-09-10T14:32:00Z"})
    )

    async with Nova3DClient(token=None, base_url=BASE_URL) as client:
        token = await client.exchange_mcp_session_code("session-code")

    assert token == "n3d_test_session"


@pytest.mark.asyncio
async def test_exchange_mcp_session_returns_expires_at(mock_api):
    mock_api.post("/mcp/session/exchange").mock(
        return_value=httpx.Response(200, json={"token": "n3d_test_session", "expires_at": "2026-09-10T14:32:00Z"})
    )

    async with Nova3DClient(token=None, base_url=BASE_URL) as client:
        exchange = await client.exchange_mcp_session("session-code")

    assert exchange.token == "n3d_test_session"
    assert exchange.expires_at == "2026-09-10T14:32:00Z"


@pytest.mark.asyncio
async def test_exchange_mcp_session_code_missing_token_raises(mock_api):
    mock_api.post("/mcp/session/exchange").mock(
        return_value=httpx.Response(200, json={"ok": True})
    )

    async with Nova3DClient(token=None, base_url=BASE_URL) as client:
        with pytest.raises(Nova3DError, match="did not return a Nova3D credential"):
            await client.exchange_mcp_session_code("session-code")


@pytest.mark.asyncio
async def test_create_conversation_success(mock_api):
    mock_api.post("/conversations").mock(
        return_value=httpx.Response(201, json={
            "id": "conv-abc123",
            "tenant_id": "ten_abc",
            "user_id": "user-1",
            "source": "mcp",
            "kind": "generation",
            "status": "open",
            "title": "a toaster with removable tray",
            "external_conversation_id": None,
            "conversation_metadata": None,
            "created_at": "2026-05-30T12:00:00Z",
            "updated_at": "2026-05-30T12:00:00Z",
            "last_message_at": None,
        })
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        conv_id = await client.create_conversation(title="a toaster with removable tray")

    assert conv_id == "conv-abc123"


@pytest.mark.asyncio
async def test_create_conversation_auth_error(mock_api):
    mock_api.post("/conversations").mock(
        return_value=httpx.Response(401, json={
            "detail": {"code": "invalid_api_key", "message": "Bad key."}
        })
    )

    async with Nova3DClient(token="n3d_bad", base_url=BASE_URL) as client:
        with pytest.raises(Nova3DAuthError):
            await client.create_conversation(title="a robot")


@pytest.mark.asyncio
async def test_create_conversation_missing_id_raises(mock_api):
    mock_api.post("/conversations").mock(
        return_value=httpx.Response(201, json={"source": "mcp", "kind": "generation"})
    )
    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        with pytest.raises(Nova3DError, match="did not return an ID"):
            await client.create_conversation(title="a robot")


@pytest.mark.asyncio
async def test_update_conversation_snapshot_sends_flutter_metadata(mock_api):
    captured_requests = []

    def capture_and_respond(request, route):
        captured_requests.append(request)
        return httpx.Response(200, json={"id": "conv-abc123"})

    mock_api.patch("/conversations/conv-abc123").mock(
        side_effect=capture_and_respond
    )
    messages = [
        {
            "id": "cad-state-123",
            "role": "assistant",
            "text": "Your 3D model is ready.",
            "created_at": "2026-06-07T00:00:00Z",
            "is_streaming": False,
            "model_url": "https://nova3d.xyz/assets/abc.glb",
        }
    ]

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        await client.update_conversation_snapshot(
            "conv-abc123",
            title="a robot",
            messages=messages,
        )

    parsed = json.loads(captured_requests[0].content)
    assert parsed["title"] == "a robot"
    snapshot = parsed["conversation_metadata"]["nova3d_chat_snapshot"]
    assert snapshot["schema_version"] == 1
    assert snapshot["messages"] == messages


@pytest.mark.asyncio
async def test_append_conversation_message_sends_content_json(mock_api):
    captured_requests = []

    def capture_and_respond(request, route):
        captured_requests.append(request)
        return httpx.Response(201, json={"id": "msg-remote"})

    mock_api.post("/conversations/conv-abc123/messages").mock(
        side_effect=capture_and_respond
    )
    message = {
        "id": "cad-state-123",
        "role": "assistant",
        "text": "Your 3D model is ready.",
        "created_at": "2026-06-07T00:00:00Z",
        "is_streaming": False,
        "workflow_id": "state-123",
    }

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        remote_id = await client.append_conversation_message(
            "conv-abc123",
            message,
        )

    parsed = json.loads(captured_requests[0].content)
    assert remote_id == "msg-remote"
    assert parsed["client_message_id"] == "cad-state-123"
    assert parsed["status"] == "completed"
    assert parsed["content_json"] == message


@pytest.mark.asyncio
async def test_link_workflow_to_message_sends_mcp_metadata(mock_api):
    captured_requests = []

    def capture_and_respond(request, route):
        captured_requests.append(request)
        return httpx.Response(201, json={"id": "link-1"})

    mock_api.post("/conversations/conv-abc123/workflow-links").mock(
        side_effect=capture_and_respond
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        await client.link_workflow_to_message(
            "conv-abc123",
            workflow_id="state-123",
            remote_message_id="msg-remote",
            operation="initial_generation",
        )

    parsed = json.loads(captured_requests[0].content)
    assert parsed["workflow_id"] == "state-123"
    assert parsed["message_id"] == "msg-remote"
    assert parsed["relation_type"] == "message_result"
    assert parsed["link_metadata"]["client"] == "mcp"


def test_result_parsing_api_key_source_present():
    data = {
        "final_latest_valid": [
            {
                "status": "completed",
                "ok": True,
                "glb_artifact": {"url": "https://nova3d.xyz/assets/abc123.glb"},
                "model_artifact": {"url": "https://nova3d.xyz/assets/abc123.glb"},
                "code_artifact": {"content": "import bpy"},
                "api_key_source": "request",
            }
        ]
    }
    result = GenerationResult.from_api(data, WORKFLOW_ID)
    assert result.api_key_source == "request"


def test_result_parsing_api_key_source_absent():
    result = GenerationResult.from_api(_result_ok(), WORKFLOW_ID)
    assert result.api_key_source is None


# ── Startup validation tests ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_validate_startup_no_token(monkeypatch, capsys):
    import nova3d_mcp.server as server_module
    server_module._startup_error = None
    monkeypatch.delenv("NOVA3D_TOKEN", raising=False)
    await _validate_startup()
    assert server_module._startup_error is None
    captured = capsys.readouterr()
    assert captured.err == ""
    server_module._startup_error = None


@pytest.mark.asyncio
async def test_validate_startup_success(mock_api, monkeypatch, capsys):
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_validkey")
    mock_api.get("/me").mock(
        return_value=httpx.Response(200, json={
            "user_id": "abc",
            "email": "test@example.com",
            "available_credits": 0,
            "tenant_id": "ten_abc",
        })
    )
    await _validate_startup()  # must not raise
    captured = capsys.readouterr()
    assert "test@example.com" in captured.err


@pytest.mark.asyncio
async def test_validate_startup_revoked_key(mock_api, monkeypatch, capsys):
    import nova3d_mcp.server as server_module
    server_module._startup_error = None
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_revoked")
    mock_api.get("/me").mock(
        return_value=httpx.Response(401, json={
            "detail": {"code": "api_key_revoked", "message": "Revoked."}
        })
    )
    await _validate_startup()
    assert server_module._startup_error is None
    captured = capsys.readouterr()
    assert "revoked" in captured.err.lower()
    server_module._startup_error = None


@pytest.mark.asyncio
async def test_validate_startup_network_error(monkeypatch, capsys):
    import nova3d_mcp.server as server_module
    server_module._startup_error = None
    monkeypatch.setenv("NOVA3D_TOKEN", "n3d_testkey")
    with respx.mock(base_url=BASE_URL) as mock:
        mock.get("/me").mock(side_effect=httpx.NetworkError("Connection refused"))
        await _validate_startup()
    assert server_module._startup_error is not None
    assert "connection" in server_module._startup_error.lower() or "network" in server_module._startup_error.lower()
    captured = capsys.readouterr()
    assert "connection" in captured.err.lower() or "network" in captured.err.lower()
    server_module._startup_error = None


def test_result_parsing_parts_from_code_artifact():
    data = {
        "final_latest_valid": [
            {
                "status": "completed",
                "ok": True,
                "glb_artifact": {"url": "https://nova3d.xyz/assets/abc123.glb"},
                "model_artifact": {"url": "https://nova3d.xyz/assets/abc123.glb"},
                "code_artifact": {
                    "content": (
                        "import bpy\n"
                        "bpy.ops.mesh.primitive_cube_add()\n"
                        "obj = bpy.context.active_object\n"
                        "obj.name = \"body\"\n"
                        "bpy.ops.mesh.primitive_cylinder_add()\n"
                        "wheel = bpy.context.active_object\n"
                        "wheel.name = \"wheel_fr\"\n"
                    )
                },
            }
        ]
    }
    result = GenerationResult.from_api(data, WORKFLOW_ID)
    assert result.parts == ["body", "wheel_fr"]


def test_result_parsing_parts_api_field_takes_precedence():
    data = {
        "final_latest_valid": [
            {
                "status": "completed",
                "ok": True,
                "glb_artifact": {"url": "https://nova3d.xyz/assets/abc123.glb"},
                "model_artifact": {"url": "https://nova3d.xyz/assets/abc123.glb"},
                "code_artifact": {
                    "content": 'obj.name = "should_not_appear"'
                },
                "parts": ["door", "frame"],
            }
        ]
    }
    result = GenerationResult.from_api(data, WORKFLOW_ID)
    assert result.parts == ["door", "frame"]


@pytest.mark.asyncio
async def test_generate_sends_conversation_id(mock_api):
    """When conversation_id is provided, _start_workflow includes it in the request body."""
    captured_requests = []

    def capture_and_respond(request, route):
        captured_requests.append(request)
        return httpx.Response(202, json=_start_ok())

    mock_api.get("/workflow/readiness/sketch_to_3d_v2").mock(
        return_value=httpx.Response(200, json=_readiness_ok())
    )
    mock_api.post("/run/state/sketch_to_3d_v2").mock(side_effect=capture_and_respond)
    mock_api.get(f"/status/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_status_completed())
    )
    mock_api.get(f"/result/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_result_ok())
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        import nova3d_mcp.client as client_module
        original_sleep = client_module.asyncio.sleep
        client_module.asyncio.sleep = lambda _: original_sleep(0)

        await client.generate(
            prompt="a toaster",
            code_llm_profile="nova3d_code_generation",
            code_llm_tier="gemini_3_1_pro_google",
            conversation_id="conv-abc123",
        )

        client_module.asyncio.sleep = original_sleep

    assert len(captured_requests) == 1
    parsed = json.loads(captured_requests[0].content)
    assert parsed["conversation"]["conversation_id"] == "conv-abc123"
    assert parsed["conversation"]["relation_type"] == "initial_generation"
    assert parsed["conversation"]["link_metadata"]["operation"] == "sketch_to_3d_v2"
    assert parsed["payload"]["code_llm_profile"] == "nova3d_code_generation"
    assert parsed["payload"]["code_llm_tier"] == "gemini_3_1_pro_google"
    assert parsed["return_nodes"] == [
        "final_validated_correction",
        "final_latest_valid",
        "fail_generation",
    ]


@pytest.mark.asyncio
async def test_generate_omits_conversation_when_none(mock_api):
    """When no conversation_id, the conversation key is absent from the request body."""
    captured_requests = []

    def capture_and_respond(request, route):
        captured_requests.append(request)
        return httpx.Response(202, json=_start_ok())

    mock_api.get("/workflow/readiness/sketch_to_3d_v2").mock(
        return_value=httpx.Response(200, json=_readiness_ok())
    )
    mock_api.post("/run/state/sketch_to_3d_v2").mock(side_effect=capture_and_respond)
    mock_api.get(f"/status/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_status_completed())
    )
    mock_api.get(f"/result/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_result_ok())
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        import nova3d_mcp.client as client_module
        original_sleep = client_module.asyncio.sleep
        client_module.asyncio.sleep = lambda _: original_sleep(0)

        await client.generate(
            prompt="a toaster",
            code_llm_profile="nova3d_code_generation",
            code_llm_tier="gemini_3_1_pro_google",
        )

        client_module.asyncio.sleep = original_sleep

    parsed = json.loads(captured_requests[0].content)
    assert "conversation" not in parsed


@pytest.mark.asyncio
async def test_regenerate_part_sends_edit_conversation_metadata(mock_api):
    captured_requests = []

    def capture_and_respond(request, route):
        captured_requests.append(request)
        return httpx.Response(202, json=_start_ok())

    mock_api.post("/run/state/regenerate_3d_part").mock(side_effect=capture_and_respond)
    mock_api.get(f"/status/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_status_completed())
    )
    mock_api.get(f"/result/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_result_ok())
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        import nova3d_mcp.client as client_module
        original_sleep = client_module.asyncio.sleep
        client_module.asyncio.sleep = lambda _: original_sleep(0)

        await client.regenerate_part(
            code_artifact={"content": "import bpy"},
            part_type="door",
            description="glass door",
            provider="gemini",
            llm="gemini",
            conversation_id="conv-abc123",
        )

        client_module.asyncio.sleep = original_sleep

    parsed = json.loads(captured_requests[0].content)
    assert parsed["conversation"]["relation_type"] == "regenerate_3d_part"
    assert parsed["conversation"]["link_metadata"]["operation"] == "regenerate_3d_part"


@pytest.mark.asyncio
async def test_add_part_sends_edit_conversation_metadata(mock_api):
    captured_requests = []

    def capture_and_respond(request, route):
        captured_requests.append(request)
        return httpx.Response(202, json=_start_ok())

    mock_api.post("/run/state/add_3d_part").mock(side_effect=capture_and_respond)
    mock_api.get(f"/status/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_status_completed())
    )
    mock_api.get(f"/result/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_result_ok())
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        import nova3d_mcp.client as client_module
        original_sleep = client_module.asyncio.sleep
        client_module.asyncio.sleep = lambda _: original_sleep(0)

        await client.add_part(
            code_artifact={"content": "import bpy"},
            description="chrome handle",
            provider="gemini",
            llm="gemini",
            conversation_id="conv-abc123",
        )

        client_module.asyncio.sleep = original_sleep

    parsed = json.loads(captured_requests[0].content)
    assert parsed["conversation"]["relation_type"] == "add_3d_part"
    assert parsed["conversation"]["link_metadata"]["operation"] == "add_3d_part"


@pytest.mark.asyncio
async def test_articulate_model_sends_edit_conversation_metadata(mock_api):
    captured_requests = []

    def capture_and_respond(request, route):
        captured_requests.append(request)
        return httpx.Response(202, json=_start_ok())

    mock_api.post("/run/state/articulate_3d_model").mock(side_effect=capture_and_respond)
    mock_api.get(f"/status/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_status_completed())
    )
    mock_api.get(f"/result/{WORKFLOW_ID}").mock(
        return_value=httpx.Response(200, json=_result_ok())
    )

    async with Nova3DClient(token=FAKE_TOKEN, base_url=BASE_URL) as client:
        import nova3d_mcp.client as client_module
        original_sleep = client_module.asyncio.sleep
        client_module.asyncio.sleep = lambda _: original_sleep(0)

        await client.articulate_model(
            code_artifact={"content": "import bpy"},
            articulation_request="make the door swing",
            provider="gemini",
            llm="gemini",
            model_url="https://nova3d.xyz/assets/abc123.glb",
            conversation_id="conv-abc123",
        )

        client_module.asyncio.sleep = original_sleep

    parsed = json.loads(captured_requests[0].content)
    assert parsed["conversation"]["relation_type"] == "articulate_model"
    assert parsed["conversation"]["link_metadata"]["operation"] == "articulate_3d_model"


def test_result_parsing_v2_corrected_output():
    result = GenerationResult.from_api(_result_corrected_ok(), WORKFLOW_ID)
    assert result.failed is False
    assert result.glb_url == "https://nova3d.xyz/assets/corrected.glb"
    assert result.model_artifact["url"] == "https://nova3d.xyz/assets/corrected.glb"


def test_status_progress_label_for_v2_node():
    from nova3d_mcp.models import WorkflowStatus

    status = WorkflowStatus.from_api(
        WORKFLOW_ID,
        {
            "runtime": {"state": "running", "last_exit_node_id": None},
            "node_visit_seq": {"validation_llm": 1},
        },
    )
    assert status.progress_label == "Reviewing the generated model..."
