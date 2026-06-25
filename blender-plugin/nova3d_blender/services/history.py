# SPDX-License-Identifier: MIT
"""Builds and persists the conversation/message records that make a Blender
generation appear in the web app's chat history, fully interactive.

The web client reconstructs a conversation from two complementary sources that
it merges (`ConversationRepository._mergeMessages`):

  1. The chat *snapshot* embedded in `conversation_metadata`
     (`nova3d_chat_snapshot`), written via PATCH /conversations/{id}.
  2. Appended *messages* (POST /conversations/{id}/messages), each linked to its
     workflow via POST /conversations/{id}/workflow-links.

We write both, using the exact `content_json` shape produced by
`MessageModel.toContentJson` in the web client, so the model preview, code, and
joints all render when the user opens the conversation in the browser.

Pure payload builders here are `bpy`-free; `persist` performs the network calls.
"""

from datetime import datetime, timezone

from .. import constants

_SNAPSHOT_KEY = "nova3d_chat_snapshot"
_READY_TEXT = "Your 3D model is ready."


def _utc_iso():
    return datetime.now(timezone.utc).isoformat()


def _user_message(*, message_id, created_at, prompt, image_data_urls):
    """Replicates a user MessageModel.toContentJson()."""
    msg = {
        "id": message_id,
        "role": "user",
        "text": prompt,
        "created_at": created_at,
        "is_streaming": False,
    }
    if image_data_urls:
        msg["image_data_url"] = image_data_urls[0]
        msg["image_data_urls"] = list(image_data_urls)
    return msg


def _assistant_message(*, message_id, created_at, workflow_id, parsed, model_option,
                       prompt):
    """Replicates an assistant MessageModel.toContentJson() for a finished asset.

    Only includes keys when their value is present, matching the web client's
    conditional serialisation exactly (so a round-trip is byte-faithful).
    """
    option_id, label, _tier, _credits, _badge = model_option
    msg = {
        "id": message_id,
        "role": "assistant",
        "text": _READY_TEXT,
        "created_at": created_at,
        "is_streaming": False,
        "operation": "initial_generation",
        "model_option_id": option_id,
        "model_label": label,
    }
    if parsed.glb_url:
        msg["model_url"] = parsed.glb_url
        msg["source_model_url"] = parsed.glb_url
    if workflow_id:
        msg["workflow_id"] = workflow_id
    if parsed.model_artifact:
        msg["model_artifact"] = parsed.model_artifact
    if parsed.code_artifact:
        msg["code_artifact"] = parsed.code_artifact
    if parsed.joints_artifact:
        msg["joints_artifact"] = parsed.joints_artifact
    if parsed.joints:
        msg["joints"] = parsed.joints
    if prompt:
        msg["instruction_prompt"] = prompt
    return msg


def build_messages(*, user_message_id, assistant_message_id, prompt, image_data_urls,
                   workflow_id, parsed, model_option):
    """Return (user_msg, assistant_msg) content_json dicts."""
    created_at = _utc_iso()
    user = _user_message(
        message_id=user_message_id, created_at=created_at, prompt=prompt,
        image_data_urls=image_data_urls,
    )
    assistant = _assistant_message(
        message_id=assistant_message_id, created_at=created_at,
        workflow_id=workflow_id, parsed=parsed, model_option=model_option,
        prompt=prompt,
    )
    return user, assistant


def build_snapshot_metadata(messages):
    """Wrap content_json messages into the conversation_metadata snapshot."""
    return {
        _SNAPSHOT_KEY: {
            "schema_version": 1,
            "updated_at": _utc_iso(),
            "messages": list(messages),
        }
    }


def persist(client, *, conversation_id, title, user_msg, assistant_msg, workflow_id):
    """Write the snapshot + both messages + the workflow link.

    Best-effort and isolated: a history failure must never fail an otherwise
    successful generation (the asset is already on disk). Returns the remote
    assistant message id when available, else None.
    """
    # 1. Snapshot — what the web chat view reads first.
    client.patch_conversation_snapshot(
        conversation_id,
        title=title,
        metadata=build_snapshot_metadata([user_msg, assistant_msg]),
    )

    # 2. Stable per-message append (timeline view) + workflow link on the asset.
    client.append_message(
        conversation_id,
        client_message_id=user_msg["id"], role="user",
        content_text=user_msg["text"], content_json=user_msg,
        sent_at=user_msg["created_at"],
    )
    receipt = client.append_message(
        conversation_id,
        client_message_id=assistant_msg["id"], role="assistant",
        content_text=assistant_msg["text"], content_json=assistant_msg,
        sent_at=assistant_msg["created_at"],
    )
    remote_id = (receipt or {}).get("id")
    if remote_id and workflow_id:
        client.link_workflow_to_message(
            conversation_id, workflow_id=workflow_id, message_id=remote_id,
            operation="initial_generation",
        )
    return remote_id


def conversation_title(prompt):
    """First-message title, matching the web client's 50-char truncation."""
    text = (prompt or "Untitled generation").strip() or "Untitled generation"
    return text[:50] + "..." if len(text) > 50 else text


def start_link(conversation_id):
    """The `conversation` block sent with POST /run/state to link the workflow."""
    return {
        "conversation_id": conversation_id,
        "relation_type": "initial_generation",
        "link_metadata": {
            "operation": constants.WORKFLOW_NAME,
            "client": constants.CLIENT_NAME,
        },
    }
