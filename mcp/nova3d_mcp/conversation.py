"""
Conversation history helpers for Nova3D's web app.

The Flutter client stores generated assets as chat messages with a stable JSON
shape. The MCP server writes the same shape so /chat/<conversation_id> opens a
hydrated generation history instead of an empty conversation shell.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from nova3d_mcp.models import GenerationResult

CHAT_SNAPSHOT_KEY = "nova3d_chat_snapshot"


def build_generation_messages(
    *,
    prompt: str,
    result: GenerationResult,
    code_artifact: Optional[Dict[str, Any]],
    model_option_id: str,
) -> List[Dict[str, Any]]:
    """Build the initial user prompt and assistant asset messages."""
    created_at = _utc_now()
    workflow_id = result.workflow_id
    messages = [
        {
            "id": f"user-{workflow_id}",
            "role": "user",
            "text": prompt,
            "created_at": created_at,
            "is_streaming": False,
        },
        {
            "id": f"cad-{workflow_id}",
            "role": "assistant",
            "text": "Your 3D model is ready.",
            "created_at": created_at,
            "is_streaming": False,
            "model_url": result.glb_url,
            "workflow_id": workflow_id,
            "operation": "initial_generation",
            "source_model_url": result.glb_url,
            "model_option_id": model_option_id,
            "instruction_prompt": prompt,
            **_artifact_fields(
                model_artifact=result.model_artifact,
                code_artifact=code_artifact,
                joints_artifact=result.joints_artifact,
                joints=result.joints,
            ),
        },
    ]
    return [_strip_empty(message) for message in messages]


def build_edit_message(
    *,
    operation: str,
    description: str,
    result: GenerationResult,
    code_artifact: Optional[Dict[str, Any]],
    model_option_id: str,
    instruction_prompt: Optional[str],
) -> Dict[str, Any]:
    """Build an app-compatible asset-version message for edit workflows."""
    message = {
        "id": f"edit-{result.workflow_id}",
        "role": "assistant",
        "text": _edit_completion_text(operation, description),
        "created_at": _utc_now(),
        "is_streaming": False,
        "model_url": result.glb_url,
        "workflow_id": result.workflow_id,
        "message_type": "asset_version",
        "operation": operation,
        "source_model_url": result.glb_url,
        "model_option_id": model_option_id,
        "instruction_prompt": instruction_prompt,
        **_artifact_fields(
            model_artifact=result.model_artifact,
            code_artifact=code_artifact,
            joints_artifact=result.joints_artifact,
            joints=result.joints,
        ),
    }
    return _strip_empty(message)


def build_snapshot_metadata(messages: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Build the conversation_metadata snapshot used by the Flutter app."""
    return {
        CHAT_SNAPSHOT_KEY: {
            "schema_version": 1,
            "updated_at": _utc_now(),
            "messages": messages,
        }
    }


def remote_message_payload(message: Dict[str, Any]) -> Dict[str, Any]:
    """Build POST /conversations/{id}/messages payload from content JSON."""
    return {
        "client_message_id": message["id"],
        "role": message["role"],
        "status": "pending" if message.get("is_streaming") else "completed",
        "content_text": message.get("text", ""),
        "content_json": message,
        "sent_at": message.get("created_at") or _utc_now(),
    }


def _artifact_fields(
    *,
    model_artifact: Optional[Dict[str, Any]],
    code_artifact: Optional[Dict[str, Any]],
    joints_artifact: Optional[Dict[str, Any]],
    joints: List[Dict[str, Any]],
) -> Dict[str, Any]:
    fields: Dict[str, Any] = {}
    if model_artifact is not None:
        fields["model_artifact"] = model_artifact
    if code_artifact is not None:
        fields["code_artifact"] = code_artifact
    if joints_artifact is not None:
        fields["joints_artifact"] = joints_artifact
    if joints:
        fields["joints"] = joints
    return fields


def _edit_completion_text(operation: str, description: str) -> str:
    label = {
        "add_3d_part": "Added part",
        "articulate_3d_model": "Articulated model",
    }.get(operation, "Regenerated selected part")
    clean = description.strip()
    return f"{label}: {clean}" if clean else label


def _strip_empty(message: Dict[str, Any]) -> Dict[str, Any]:
    return {
        key: value
        for key, value in message.items()
        if value is not None and value != "" and value != []
    }


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
