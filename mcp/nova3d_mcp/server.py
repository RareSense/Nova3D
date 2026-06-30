"""
nova3d_mcp/server.py
────────────────────────────────────────────────────────────────
Nova3D MCP Server.

Exposes Nova3D's structured 3D generation pipeline as MCP tools
callable from Claude Code, Cursor, and any MCP-compatible agent.

Configuration (environment variables):
    NOVA3D_TOKEN      — Advanced/manual Nova3D API key fallback (optional)
    NOVA3D_API_URL    — Override API base URL (optional)
    NOVA3D_APP_URL    — Override app URL for conversation links (optional)

Usage:
    uvx nova3d-mcp
    # or
    python -m nova3d_mcp.server
────────────────────────────────────────────────────────────────
"""
from __future__ import annotations

import asyncio
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Awaitable, Callable, Dict, List, Optional

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.server import Context

from nova3d_mcp.auth import Nova3DAuthenticator, Nova3DLoginError
from nova3d_mcp.client import Nova3DClient, Nova3DAuthError, Nova3DError, _is_recoverable
from nova3d_mcp.conversation import (
    build_edit_message,
    build_generation_messages,
)
from nova3d_mcp.models import GenerationResult, MCPStatus, WorkflowStatus, WorkflowState
from nova3d_mcp.session_store import SessionStore
from nova3d_mcp.workflow_store import WorkflowStore

load_dotenv()

# ── Startup error state ───────────────────────────────────────────────────────

_startup_error: Optional[str] = None
_pending_login: Optional["PendingLoginState"] = None

# ── Model options ─────────────────────────────────────────────────────────────

_MODEL_OPTIONS: Dict[str, Dict[str, str]] = {
    "gemini": {
        "provider": "gemini",
        "llm": "gemini",
        "code_llm_profile": "nova3d_code_generation",
        "code_llm_tier": "gemini_3_1_pro_google",
        "option_id": "credits_gemini_3_1_pro_google",
    },
    "claude-sonnet": {
        "provider": "anthropic",
        "llm": "claude-sonnet",
        "code_llm_profile": "nova3d_code_generation",
        "code_llm_tier": "claude_sonnet_4_6_anthropic",
        "option_id": "credits_claude_sonnet_4_6_anthropic",
    },
    "claude-opus": {
        "provider": "anthropic",
        "llm": "claude-opus",
        "code_llm_profile": "nova3d_code_generation",
        "code_llm_tier": "claude_opus_4_8_anthropic",
        "option_id": "credits_claude_opus_4_8_anthropic",
    },
    "claude-opus-latest": {
        "provider": "anthropic",
        "llm": "claude-opus-latest",
        "code_llm_profile": "nova3d_code_generation",
        "code_llm_tier": "claude_opus_4_8_anthropic",
        "option_id": "credits_claude_opus_4_8_anthropic",
    },
    "gpt-5.5": {
        "provider": "openai",
        "llm": "gpt55",
        "code_llm_profile": "nova3d_code_generation",
        "code_llm_tier": "gpt_5_5_openrouter",
        "option_id": "credits_gpt_5_5_openrouter",
    },
}
_DEFAULT_MODEL = "gemini"
LOGIN_GRACE_PERIOD_SECONDS = 1.0


def _resolve_model(model: Optional[str]) -> Optional[Dict[str, str]]:
    return _MODEL_OPTIONS.get((model or _DEFAULT_MODEL).strip())


@dataclass
class PendingLoginState:
    connect_url: str
    port: int
    task: "asyncio.Task[Any]"

# ── Server init ───────────────────────────────────────────────────────────────

mcp = FastMCP(
    "nova3d",
    instructions=(
        "Nova3D generates structured, part-aware 3D assets from text prompts or "
        "reference images. Unlike diffusion-based tools, Nova3D outputs named, "
        "separately editable mesh components — not fused blobs.\n\n"
        "WORKFLOW:\n"
        "1. Call generate_3d → returns glb_url (download), parts list, "
        "code_artifact, and "
        "conversation_url. Always surface conversation_url to the user — it opens "
        "a browser view of the asset and its full edit history in the Nova3D app.\n"
        "   - Initial generation runs through Nova3D's paid GraphFlow v2 path.\n"
        "   - The model selector routes to a paid Nova3D tier; this MCP server does "
        "not expose BYOK provider-key generation.\n"
        "2. Call regenerate_part, add_part, or articulate_model with the "
        "code_artifact from any prior result. These tools return an updated glb_url "
        "and the same conversation_url, linking all edits into one session.\n"
        "   - conversation_url may be absent from edit-tool responses if session "
        "creation failed silently at generate time; generation still succeeded.\n"
        "   - Always pass the most recent code_artifact forward — it carries session "
        "state that links edits together.\n\n"
        "SETUP:\n"
        "1. After installing this MCP server in your client, the next step is to call "
        "nova3d_setup or go directly to nova3d_login.\n"
        "2. Preferred: Call nova3d_login to sign in through the browser.\n"
        "3. Check nova3d_status to confirm credits and readiness before generation.\n"
        "4. Advanced fallback: you may still provide NOVA3D_TOKEN manually in "
        "non-interactive environments.\n"
        "\n"
        "If any tool returns {\"failed\": true}, surface the error_message to the user verbatim."
    ),
)


# ── Auth helper ───────────────────────────────────────────────────────────────

def _get_session_store() -> SessionStore:
    return SessionStore()


def _get_manual_token() -> Optional[str]:
    token = os.environ.get("NOVA3D_TOKEN", "").strip()
    return token or None


def _get_token() -> str:
    session_token = _get_session_store().load_token()
    if session_token:
        return session_token
    manual_token = _get_manual_token()
    if manual_token:
        return manual_token
    raise Nova3DError(
        "Sign in to Nova3D with nova3d_login to continue. "
        "Advanced fallback: set NOVA3D_TOKEN manually in your MCP config."
    )


def _get_api_url() -> str:
    return os.environ.get("NOVA3D_API_URL", "https://nova3d.xyz/api").rstrip("/")


def _get_app_url() -> str:
    return os.environ.get("NOVA3D_APP_URL", "https://app.nova3d.xyz").rstrip("/")


async def _validate_startup() -> None:
    """Validate an existing configured credential if one is present."""
    global _startup_error

    token = _get_session_store().load_token() or _get_manual_token()
    if not token:
        _startup_error = None
        return

    base_url = _get_api_url()
    try:
        async with Nova3DClient(token=token, base_url=base_url) as client:
            me = await client.get_me()
        print(f"✓ Nova3D authenticated: {me['email']}", file=sys.stderr)
    except Nova3DAuthError as e:
        _startup_error = None
        print(f"Nova3D: {e}", file=sys.stderr)
    except Nova3DError as e:
        _startup_error = (
            f"Could not reach Nova3D to verify token: {e}\n"
            "Check your connection and try again."
        )
        print(_startup_error, file=sys.stderr)


async def _get_mcp_status() -> MCPStatus:
    token = _get_session_store().load_token() or _get_manual_token()
    async with Nova3DClient(token=token, base_url=_get_api_url()) as client:
        return await client.get_mcp_status()


def _build_session_hint(session_store: SessionStore) -> Dict[str, Any]:
    expires_at = session_store.load_expires_at()
    if not expires_at:
        return {}
    hint: Dict[str, Any] = {"stored_session_expires_at": expires_at}
    parsed = _parse_iso_datetime(expires_at)
    if parsed is not None:
        now = datetime.now(timezone.utc)
        hint["session_reauth_recommended"] = parsed <= (now + timedelta(days=1))
    return hint


def _parse_iso_datetime(value: str) -> Optional[datetime]:
    normalized = value.strip()
    if not normalized:
        return None
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


async def _require_generation_ready() -> Optional[Dict[str, Any]]:
    status = await _get_mcp_status()
    if status.next_action is None and status.generation_ready and status.authenticated:
        return None

    response: Dict[str, Any] = {
        "failed": True,
        "error_message": status.user_message,
        "next_action": status.next_action,
    }
    if status.next_action_url:
        response["next_action_url"] = status.next_action_url
    if status.identity is not None:
        response["identity"] = status.identity.model_dump()
    if status.credits is not None:
        response["credits"] = status.credits.model_dump()
    if status.mcp_session is not None:
        response["mcp_session"] = status.mcp_session.model_dump()
    return response


# ── Progress helper ───────────────────────────────────────────────────────────

def _make_progress_callback(
    ctx: Optional[Context],
) -> Callable[[WorkflowStatus], Awaitable[None]]:
    """Return an async on_progress callback that reports each newly completed node."""
    seen: set = set()
    counter: List[int] = [0]

    async def on_progress(status: WorkflowStatus) -> None:
        node = status.last_exit_node or status.current_node
        if not node or node in seen:
            return
        seen.add(node)
        counter[0] += 1
        if ctx:
            await ctx.report_progress(
                progress=counter[0],
                total=None,
                message=f"Completed: {node}",
            )

    return on_progress


def _make_login_progress_callback(
    ctx: Optional[Context],
) -> Callable[[str], Awaitable[None]]:
    counter: List[int] = [0]

    async def on_progress(message: str) -> None:
        counter[0] += 1
        if ctx:
            await ctx.report_progress(
                progress=counter[0],
                total=None,
                message=message,
            )

    return on_progress


# ── Conversation linking helpers ──────────────────────────────────────────────

def _extract_conversation_id(code_artifact: Optional[Dict[str, Any]]) -> Optional[str]:
    if not isinstance(code_artifact, dict):
        return None
    return code_artifact.get("_nova3d_conversation_id") or None


def _embed_code_artifact_metadata(
    code_artifact: Optional[Dict[str, Any]],
    conversation_id: Optional[str],
    *,
    source_code_artifact: Optional[Dict[str, Any]] = None,
    prompt: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    if code_artifact is None:
        return None
    result = dict(code_artifact)
    if conversation_id:
        result["_nova3d_conversation_id"] = conversation_id
    source_prompt = (
        source_code_artifact.get("_nova3d_prompt")
        if isinstance(source_code_artifact, dict)
        else None
    )
    final_prompt = prompt or source_prompt
    if final_prompt:
        result["_nova3d_prompt"] = final_prompt
    return result


def _conversation_url(app_url: str, conversation_id: Optional[str]) -> Optional[str]:
    if not conversation_id:
        return None
    return f"{app_url}/chat/{conversation_id}"


def _build_image_artifact(
    image_base64: Optional[str],
    image_mime: Optional[str],
) -> Optional[List[str]]:
    if not image_base64:
        return None
    mime = (image_mime or "image/png").strip() or "image/png"
    return [f"data:{mime};base64,{image_base64.strip()}"]


async def _persist_generation_history(
    client: Nova3DClient,
    *,
    conversation_id: Optional[str],
    title: str,
    prompt: str,
    result: GenerationResult,
    code_artifact: Optional[Dict[str, Any]],
    model_option_id: str,
) -> bool:
    if not conversation_id:
        return False
    messages = build_generation_messages(
        prompt=prompt,
        result=result,
        code_artifact=code_artifact,
        model_option_id=model_option_id,
    )
    try:
        await client.update_conversation_snapshot(
            conversation_id,
            title=title,
            messages=messages,
        )
        await _append_and_link_messages(client, conversation_id, messages)
        return True
    except Nova3DError as e:
        print(f"Nova3D: conversation history persistence failed: {e}", file=sys.stderr)
        return False


async def _persist_edit_history(
    client: Nova3DClient,
    *,
    conversation_id: Optional[str],
    operation: str,
    description: str,
    result: GenerationResult,
    code_artifact: Optional[Dict[str, Any]],
    model_option_id: str,
    instruction_prompt: Optional[str],
) -> bool:
    if not conversation_id:
        return False
    message = build_edit_message(
        operation=operation,
        description=description,
        result=result,
        code_artifact=code_artifact,
        model_option_id=model_option_id,
        instruction_prompt=instruction_prompt,
    )
    try:
        await _append_and_link_messages(client, conversation_id, [message])
        return True
    except Nova3DError as e:
        print(f"Nova3D: edit history persistence failed: {e}", file=sys.stderr)
        return False


async def _append_and_link_messages(
    client: Nova3DClient,
    conversation_id: str,
    messages: List[Dict[str, Any]],
) -> None:
    for message in messages:
        remote_message_id = await client.append_conversation_message(
            conversation_id,
            message,
        )
        workflow_id = message.get("workflow_id")
        if workflow_id:
            await client.link_workflow_to_message(
                conversation_id,
                workflow_id=str(workflow_id),
                remote_message_id=remote_message_id,
                operation=str(message.get("operation") or "generation"),
            )


# ── Async workflow finish machinery ───────────────────────────────────────────

_EDIT_BACKEND_OPERATION = {
    "regenerate_part": "regenerate_3d_part",
    "add_part": "add_3d_part",
    "articulate_model": "articulate_3d_model",
}


def _get_workflow_store() -> WorkflowStore:
    return WorkflowStore()


async def _finish_workflow(
    client: Nova3DClient,
    workflow_id: str,
    entry: Dict[str, Any],
) -> Dict[str, Any]:
    """Fetch a terminal workflow's result, persist, cache, and build its payload."""
    result = await client.get_result(workflow_id)
    if result.failed:
        return {
            "workflow_id": workflow_id,
            "state": "failed",
            "is_terminal": True,
            "status": "failed",
            "failed": True,
            "error_message": result.error_message,
            "error_category": result.error_category,
            "retryable": result.retryable,
        }

    operation = entry.get("operation") or "generate"
    conversation_id = entry.get("conversation_id")
    model_option_id = entry.get("model_option_id") or ""
    app_url = _get_app_url()

    updated_code_artifact = _embed_code_artifact_metadata(
        result.code_artifact,
        conversation_id,
        prompt=entry.get("prompt"),
    )

    if operation == "generate":
        history_persisted = await _persist_generation_history(
            client,
            conversation_id=conversation_id,
            title=entry.get("title") or "",
            prompt=entry.get("prompt") or "",
            result=result,
            code_artifact=updated_code_artifact,
            model_option_id=model_option_id,
        )
        payload: Dict[str, Any] = {
            "glb_url": result.glb_url,
            "joint_count": result.joint_count,
            "joints": result.joints,
            "code_artifact": updated_code_artifact,
            "model_artifact": result.model_artifact,
        }
    else:
        history_persisted = await _persist_edit_history(
            client,
            conversation_id=conversation_id,
            operation=_EDIT_BACKEND_OPERATION.get(operation, operation),
            description=entry.get("description") or "",
            result=result,
            code_artifact=updated_code_artifact,
            model_option_id=model_option_id,
            instruction_prompt=entry.get("prompt"),
        )
        if operation == "articulate_model":
            payload = {
                "glb_url": result.glb_url,
                "joints": result.joints,
                "joint_count": result.joint_count,
                "code_artifact": updated_code_artifact,
            }
        else:
            payload = {
                "glb_url": result.glb_url,
                "code_artifact": updated_code_artifact,
            }

    payload.update(
        {
            "workflow_id": workflow_id,
            "state": "completed",
            "is_terminal": True,
            "status": "completed",
            "api_key_source": result.api_key_source,
            "history_persisted": history_persisted,
            "failed": False,
        }
    )
    conv_url = _conversation_url(app_url, conversation_id)
    if conv_url:
        payload["conversation_url"] = conv_url

    _get_workflow_store().complete(workflow_id, payload)
    return payload


def _status_payload(status: MCPStatus) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "authenticated": status.authenticated,
        "generation_ready": status.generation_ready,
        "next_action": status.next_action,
        "next_action_url": status.next_action_url,
        "user_message": status.user_message,
        "mcp_session": status.mcp_session.model_dump(),
    }
    if status.identity is not None:
        payload["identity"] = status.identity.model_dump()
    if status.credits is not None:
        payload["credits"] = status.credits.model_dump()
    payload.update(_build_session_hint(_get_session_store()))
    return payload


def _pending_login_payload(pending: PendingLoginState) -> Dict[str, Any]:
    return {
        "login_started": True,
        "login_pending_confirmation": True,
        "browser_url": pending.connect_url,
        "local_callback_port": pending.port,
        "user_message": (
            "Complete Nova3D sign-in in the browser tab that opened, then call nova3d_status "
            "to confirm credits and readiness."
        ),
        "suggested_next_step": "call nova3d_status",
    }


def _structured_login_error_payload(
    error: Nova3DLoginError,
    *,
    browser_url: Optional[str] = None,
) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "failed": True,
        "error_message": str(error),
    }
    if browser_url or error.browser_url:
        payload["browser_url"] = browser_url or error.browser_url
    if error.should_check_status:
        payload["suggested_next_step"] = "call nova3d_status"
        payload["recovery_instructions"] = (
            "If you completed sign-in in the browser, call nova3d_status now. "
            "If status still shows not signed in, retry nova3d_login."
        )
    if error.manual_fallback_only:
        payload["manual_fallback_available"] = True
    return payload


async def _consume_pending_login_result() -> Optional[Dict[str, Any]]:
    global _pending_login

    pending = _pending_login
    if pending is None or not pending.task.done():
        return None

    _pending_login = None
    try:
        result = await pending.task
    except Nova3DLoginError as e:
        return _structured_login_error_payload(e, browser_url=pending.connect_url)
    except Exception:
        return {
            "failed": True,
            "browser_url": pending.connect_url,
            "suggested_next_step": "call nova3d_status",
            "error_message": (
                "Nova3D browser sign-in may have completed, but the MCP session could not be confirmed yet. "
                "Call nova3d_status now. If status still shows not signed in, retry nova3d_login."
            ),
        }

    payload = _status_payload(result.status)
    payload["browser_url"] = result.connect_url
    payload["local_session_path"] = str(_get_session_store().path)
    payload["login_started"] = True
    if result.expires_at:
        payload["stored_session_expires_at"] = result.expires_at
    return payload


# ── Tools ─────────────────────────────────────────────────────────────────────

@mcp.tool()
async def nova3d_setup() -> Dict[str, Any]:
    """
    Get setup instructions for Nova3D.

    Call this if the user asks how to get started or needs the sign-in flow.

    Returns:
        instructions: Step-by-step setup guide with URL and install command.
    """
    instructions = (
        "After installing the Nova3D MCP server in Claude, Codex, Cursor, VS Code, "
        "Visual Studio, or another MCP client, your next step is not generation yet.\n\n"
        "Preferred setup:\n"
        "1. Call nova3d_login from inside your MCP client.\n"
        "2. Complete the Nova3D sign-in flow in the browser tab that opens.\n"
        "3. Then call nova3d_status to confirm credits and readiness.\n"
        "4. If credits are required, use the purchase link returned by nova3d_status.\n"
        "5. Only after authenticated: true and generation_ready: true should you call generate_3d.\n"
        "6. Manual NOVA3D_TOKEN setup is advanced fallback only if browser/loopback auth is unavailable.\n\n"
        "Advanced/manual fallback:\n"
        "claude mcp add nova3d -e NOVA3D_TOKEN=n3d_your-key -- uvx nova3d-mcp"
    )
    return {"instructions": instructions}


@mcp.tool()
async def nova3d_status() -> Dict[str, Any]:
    """
    Get the canonical Nova3D onboarding and readiness state.

    Use this before generation, after sign-in, or after purchasing credits.
    """
    pending_result = await _consume_pending_login_result()
    if pending_result is not None:
        return pending_result

    status = await _get_mcp_status()
    payload = _status_payload(status)
    if _pending_login is not None and not _pending_login.task.done():
        payload.update(_pending_login_payload(_pending_login))
    return payload


@mcp.tool()
async def nova3d_login(ctx: Optional[Context] = None) -> Dict[str, Any]:
    """
    Sign in to Nova3D through the browser and establish a local MCP session.

    This is the preferred onboarding path. It starts a loopback callback flow,
    opens a browser tab, waits for the local loopback callback, exchanges the
    one-time session code for an MCP credential, stores it locally, and returns
    the resulting readiness state.

    If browser sign-in finishes but local completion is ambiguous, call
    nova3d_status before falling back to manual NOVA3D_TOKEN setup.
    """
    global _pending_login

    finished_payload = await _consume_pending_login_result()
    if finished_payload is not None:
        return finished_payload

    if _pending_login is not None and not _pending_login.task.done():
        return _pending_login_payload(_pending_login)

    authenticator = Nova3DAuthenticator(
        base_url=_get_api_url(),
        app_url=_get_app_url(),
        session_store=_get_session_store(),
    )
    try:
        pending = await authenticator.begin_login(
            on_progress=_make_login_progress_callback(ctx),
        )
        _pending_login = PendingLoginState(
            connect_url=pending.connect_url,
            port=pending.port,
            task=pending.task,
        )
        try:
            result = await asyncio.wait_for(
                asyncio.shield(pending.task),
                timeout=LOGIN_GRACE_PERIOD_SECONDS,
            )
        except asyncio.TimeoutError:
            return _pending_login_payload(_pending_login)
        _pending_login = None
    except Nova3DLoginError as e:
        return _structured_login_error_payload(e)
    except Exception:
        return {
            "failed": True,
            "error_message": (
                "Nova3D sign-in started, but the local MCP session could not be confirmed yet. "
                "Call nova3d_status now. If status still shows not signed in, retry nova3d_login."
            ),
            "suggested_next_step": "call nova3d_status",
        }
    payload = _status_payload(result.status)
    payload["browser_url"] = result.connect_url
    payload["local_session_path"] = str(_get_session_store().path)
    payload["login_started"] = True
    if result.expires_at:
        payload["stored_session_expires_at"] = result.expires_at
    return payload


@mcp.tool()
async def nova3d_logout() -> Dict[str, Any]:
    """
    Clear the locally stored MCP session credential.

    This does not remove an advanced/manual NOVA3D_TOKEN from the MCP config.
    """
    store = _get_session_store()
    had_session = store.load_token() is not None
    store.clear()
    return {
        "logged_out": True,
        "cleared_local_session": had_session,
        "manual_token_still_configured": _get_manual_token() is not None,
    }


@mcp.tool()
async def generate_3d(
    prompt: str,
    model: Optional[str] = None,
    image_base64: Optional[str] = None,
    image_mime: Optional[str] = None,
    ctx: Optional[Context] = None,
) -> Dict[str, Any]:
    """
    Submit a structured, part-aware 3D generation from a text prompt.

    Initial generation uses Nova3D's paid GraphFlow v2 workflow. The selected
    model routes to a Nova3D-managed paid tier; this MCP tool does not expose
    BYOK provider-key generation.

    This tool is ASYNCHRONOUS: it submits the workflow and returns a
    workflow_id immediately — it does NOT wait for the model. Poll
    get_generation_status(workflow_id) until is_terminal is true; on completion
    that call returns the full result (glb_url, code_artifact, …).

    Args:
        prompt:       Description of the 3D asset. Be specific about parts.
                      Example: "a washing machine with drum, door, control panel,
                      and hose connectors"
        model:        Paid Nova3D routing preset. One of: "gemini" (default),
                      "claude-sonnet", "claude-opus", "claude-opus-latest",
                      "gpt-5.5".
        image_base64: Optional reference image as plain base64. The MCP server
                      converts this into the v2 image_artifact data-URL format.
        image_mime:   MIME type of the reference image e.g. "image/jpeg".

    Returns:
        workflow_id:       Identifier to poll with get_generation_status.
        status:            "running" on a successful submit.
        conversation_url:  Browser URL for the editing session in the Nova3D app.
                           Present only if conversation creation succeeded.
        failed:            True if the submit itself failed (then error_message
                           is set and no workflow_id is returned).
        error_message:     Human-readable error if failed is True.
    """
    if _startup_error:
        return {"failed": True, "error_message": _startup_error}
    readiness_error = await _require_generation_ready()
    if readiness_error is not None:
        return readiness_error
    model_opts = _resolve_model(model)
    if model_opts is None:
        valid = ", ".join(_MODEL_OPTIONS)
        return {"failed": True, "error_message": f"Invalid model '{model or _DEFAULT_MODEL}'. Valid options: {valid}"}
    token = _get_token()
    base_url = _get_api_url()
    app_url = _get_app_url()

    async with Nova3DClient(token=token, base_url=base_url) as client:
        conversation_id: Optional[str] = None
        try:
            conversation_id = await client.create_conversation(title=prompt[:100])
        except Exception as e:
            print(f"Nova3D: conversation creation failed (generation will proceed): {e}", file=sys.stderr)

        workflow_id = await client.start_generate(
            prompt=prompt,
            code_llm_profile=model_opts["code_llm_profile"],
            code_llm_tier=model_opts["code_llm_tier"],
            image_artifact=_build_image_artifact(image_base64, image_mime),
            conversation_id=conversation_id,
        )

    _get_workflow_store().put(
        workflow_id,
        operation="generate",
        conversation_id=conversation_id,
        prompt=prompt,
        description=None,
        title=prompt[:100],
        model_option_id=model_opts["option_id"],
    )

    response: Dict[str, Any] = {
        "workflow_id": workflow_id,
        "status": "running",
        "failed": False,
    }
    conv_url = _conversation_url(app_url, conversation_id)
    if conv_url:
        response["conversation_url"] = conv_url
    return response


@mcp.tool()
async def regenerate_part(
    code_artifact: Dict[str, Any],
    part_type: str,
    description: str,
    model: Optional[str] = None,
    ctx: Optional[Context] = None,
) -> Dict[str, Any]:
    """
    Submit a regeneration of one named part within an existing 3D asset.

    Use this after generate_3d to change one component without rebuilding the
    whole asset. Pass a natural part name (e.g. "seat", "door", "drum") — derive
    it from your original prompt or the conversation viewer; the backend
    resolves it against the asset. There is no fixed list of part names.

    This tool is ASYNCHRONOUS: it returns a workflow_id immediately. Poll
    get_generation_status(workflow_id) until is_terminal; on completion that
    call returns the updated glb_url and code_artifact.

    Args:
        code_artifact: The code_artifact object from a prior generate_3d or edit
                       result. Required — it carries the current asset structure
                       and the session link.
        part_type:     Natural name of the part to regenerate, e.g. "door",
                       "handle", "drum", "control_panel".
        description:   What the regenerated part should look like. Be specific,
                       e.g. "glass panel door with chrome frame".
        model:         LLM model. One of: "gemini" (default), "claude-sonnet",
                       "claude-opus", "claude-opus-latest", "gpt-5.5".

    Returns:
        workflow_id:       Identifier to poll with get_generation_status.
        status:            "running" on a successful submit.
        conversation_url:  Browser URL for the editing session, if linked.
        failed:            True if the submit failed (then error_message is set).
        error_message:     Human-readable error if failed is True.
    """
    if _startup_error:
        return {"failed": True, "error_message": _startup_error}
    model_opts = _resolve_model(model)
    if model_opts is None:
        valid = ", ".join(_MODEL_OPTIONS)
        return {"failed": True, "error_message": f"Invalid model '{model or _DEFAULT_MODEL}'. Valid options: {valid}"}
    token = _get_token()
    base_url = _get_api_url()
    app_url = _get_app_url()
    conversation_id = _extract_conversation_id(code_artifact)
    carried_prompt = code_artifact.get("_nova3d_prompt") if isinstance(code_artifact, dict) else None

    async with Nova3DClient(token=token, base_url=base_url) as client:
        workflow_id = await client.start_regenerate_part(
            code_artifact=code_artifact,
            part_type=part_type,
            description=description,
            provider=model_opts["provider"],
            llm=model_opts["llm"],
            conversation_id=conversation_id,
        )

    _get_workflow_store().put(
        workflow_id,
        operation="regenerate_part",
        conversation_id=conversation_id,
        prompt=carried_prompt,
        description=description,
        title=None,
        model_option_id=model_opts["option_id"],
    )

    response: Dict[str, Any] = {
        "workflow_id": workflow_id,
        "status": "running",
        "failed": False,
    }
    conv_url = _conversation_url(app_url, conversation_id)
    if conv_url:
        response["conversation_url"] = conv_url
    return response


@mcp.tool()
async def add_part(
    code_artifact: Dict[str, Any],
    description: str,
    model: Optional[str] = None,
    ctx: Optional[Context] = None,
) -> Dict[str, Any]:
    """
    Submit the addition of a new part to an existing 3D asset.

    Use this to extend an asset with a new component after generation. Describe
    the new part; it is integrated alongside existing parts, preserving naming
    and hierarchy.

    This tool is ASYNCHRONOUS: it returns a workflow_id immediately. Poll
    get_generation_status(workflow_id) until is_terminal; on completion that
    call returns the updated glb_url and code_artifact.

    Args:
        code_artifact: The code_artifact object from a prior generate_3d or edit
                       result.
        description:   Description of the new part. Be specific about shape,
                       position relative to existing parts, and materials, e.g.
                       "add a chrome handle bar to the front face of the door".
        model:         LLM model. One of: "gemini" (default), "claude-sonnet",
                       "claude-opus", "claude-opus-latest", "gpt-5.5".

    Returns:
        workflow_id:       Identifier to poll with get_generation_status.
        status:            "running" on a successful submit.
        conversation_url:  Browser URL for the editing session, if linked.
        failed:            True if the submit failed (then error_message is set).
        error_message:     Human-readable error if failed is True.
    """
    if _startup_error:
        return {"failed": True, "error_message": _startup_error}
    model_opts = _resolve_model(model)
    if model_opts is None:
        valid = ", ".join(_MODEL_OPTIONS)
        return {"failed": True, "error_message": f"Invalid model '{model or _DEFAULT_MODEL}'. Valid options: {valid}"}
    token = _get_token()
    base_url = _get_api_url()
    app_url = _get_app_url()
    conversation_id = _extract_conversation_id(code_artifact)
    carried_prompt = code_artifact.get("_nova3d_prompt") if isinstance(code_artifact, dict) else None

    async with Nova3DClient(token=token, base_url=base_url) as client:
        workflow_id = await client.start_add_part(
            code_artifact=code_artifact,
            description=description,
            provider=model_opts["provider"],
            llm=model_opts["llm"],
            conversation_id=conversation_id,
        )

    _get_workflow_store().put(
        workflow_id,
        operation="add_part",
        conversation_id=conversation_id,
        prompt=carried_prompt,
        description=description,
        title=None,
        model_option_id=model_opts["option_id"],
    )

    response: Dict[str, Any] = {
        "workflow_id": workflow_id,
        "status": "running",
        "failed": False,
    }
    conv_url = _conversation_url(app_url, conversation_id)
    if conv_url:
        response["conversation_url"] = conv_url
    return response


@mcp.tool()
async def articulate_model(
    code_artifact: Dict[str, Any],
    articulation_request: str,
    model_url: Optional[str] = None,
    model_artifact: Optional[Dict[str, Any]] = None,
    model: Optional[str] = None,
    selected_meshes: Optional[List[str]] = None,
    ctx: Optional[Context] = None,
) -> Dict[str, Any]:
    """
    Submit articulation (joints/hinges/rotation) for an existing 3D asset.

    Use this to make parts physically movable — rotating drums, swinging doors,
    robot joints. Articulation is exported as joint definitions in the GLB.

    This tool is ASYNCHRONOUS: it returns a workflow_id immediately. Poll
    get_generation_status(workflow_id) until is_terminal; on completion that
    call returns the updated glb_url, code_artifact, joints, and joint_count.

    Args:
        code_artifact:        The code_artifact object from a prior generation.
        articulation_request: Plain-language description of the desired
                              articulation, e.g. "make the drum rotate and the
                              door swing on a hinge at the left edge".
        model_url:            The glb_url from the prior result. Provide this or
                              model_artifact (or both). Direct HTTPS URL only.
        model_artifact:       The model_artifact object from the prior result.
        model:                LLM model. One of: "gemini" (default),
                              "claude-sonnet", "claude-opus", "claude-opus-latest",
                              "gpt-5.5".
        selected_meshes:      Optional list of mesh names to articulate. If
                              omitted, the LLM infers them from the request.

    Returns:
        workflow_id:       Identifier to poll with get_generation_status.
        status:            "running" on a successful submit.
        conversation_url:  Browser URL for the editing session, if linked.
        failed:            True if the submit failed (then error_message is set).
        error_message:     Human-readable error if failed is True.
    """
    if _startup_error:
        return {"failed": True, "error_message": _startup_error}
    if model_url is None and model_artifact is None:
        return {
            "failed": True,
            "error_message": "Provide model_url or model_artifact from the prior generate_3d result.",
        }
    model_opts = _resolve_model(model)
    if model_opts is None:
        valid = ", ".join(_MODEL_OPTIONS)
        return {"failed": True, "error_message": f"Invalid model '{model or _DEFAULT_MODEL}'. Valid options: {valid}"}
    token = _get_token()
    base_url = _get_api_url()
    app_url = _get_app_url()
    conversation_id = _extract_conversation_id(code_artifact)
    instruction_prompt = code_artifact.get("_nova3d_prompt") if isinstance(code_artifact, dict) else None

    async with Nova3DClient(token=token, base_url=base_url) as client:
        workflow_id = await client.start_articulate_model(
            code_artifact=code_artifact,
            articulation_request=articulation_request,
            provider=model_opts["provider"],
            llm=model_opts["llm"],
            model_url=model_url,
            model_artifact=model_artifact,
            instruction_prompt=instruction_prompt,
            selected_meshes=selected_meshes,
            conversation_id=conversation_id,
        )

    _get_workflow_store().put(
        workflow_id,
        operation="articulate_model",
        conversation_id=conversation_id,
        prompt=instruction_prompt,
        description=articulation_request,
        title=None,
        model_option_id=model_opts["option_id"],
    )

    response: Dict[str, Any] = {
        "workflow_id": workflow_id,
        "status": "running",
        "failed": False,
    }
    conv_url = _conversation_url(app_url, conversation_id)
    if conv_url:
        response["conversation_url"] = conv_url
    return response


@mcp.tool()
async def get_generation_status(workflow_id: str) -> Dict[str, Any]:
    """
    Poll a generation/edit workflow and, on completion, return its full result.

    This is THE way to obtain a result from generate_3d, regenerate_part,
    add_part, or articulate_model — those tools return a workflow_id and do not
    wait. Call this repeatedly (every ~3–5 seconds) until is_terminal is true.
    Generations typically take a few minutes; regenerate_part can take up to
    ~45 minutes.

    Args:
        workflow_id: The workflow_id returned by a generation/edit tool.

    Returns (while running):
        state, is_terminal=false, progress_label, current_node, status="running".
    Returns (on completion):
        the full result — glb_url, code_artifact, conversation_url, etc.
    Returns (on failure / unknown id):
        failed=true with error_message.
    """
    if _startup_error:
        return {"failed": True, "error_message": _startup_error}

    store = _get_workflow_store()
    entry = store.get(workflow_id)
    if entry is not None and entry.get("completed") and entry.get("result_payload") is not None:
        return entry["result_payload"]

    token = _get_token()
    base_url = _get_api_url()

    async with Nova3DClient(token=token, base_url=base_url) as client:
        try:
            status = await client.get_status(workflow_id)
        except Nova3DError as e:
            if _is_recoverable(str(e)):
                return {
                    "workflow_id": workflow_id,
                    "state": "pending",
                    "is_terminal": False,
                    "progress_label": "Starting generation...",
                    "current_node": None,
                    "status": "running",
                }
            return {"failed": True, "error_message": str(e)}

        if not status.is_terminal:
            return {
                "workflow_id": status.workflow_id,
                "state": status.state.value,
                "is_terminal": False,
                "progress_label": status.progress_label,
                "current_node": status.current_node,
                "status": "running",
            }

        # Terminal from here on.
        if status.state == WorkflowState.BUDGET_EXHAUSTED:
            return {
                "workflow_id": workflow_id,
                "state": status.state.value,
                "is_terminal": True,
                "status": "failed",
                "failed": True,
                "error_message": "Your provider or generation budget was exhausted before the model completed.",
            }

        if entry is None:
            return {
                "failed": True,
                "error_message": (
                    "Unknown or expired workflow_id. The workflow may have "
                    "finished, but its session context is no longer available "
                    "in this MCP server. Start a new generation."
                ),
            }

        return await _finish_workflow(client, workflow_id, entry)


# ── Entrypoint ────────────────────────────────────────────────────────────────

def main() -> None:
    asyncio.run(_validate_startup())
    mcp.run()


if __name__ == "__main__":
    main()
