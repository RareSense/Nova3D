"""
nova3d_mcp/models.py
────────────────────────────────────────────────────────────────
Pydantic models for Nova3D API requests and responses.
Derived from the Nova3D frontend (CadService, cad_models.dart).
────────────────────────────────────────────────────────────────
"""
from __future__ import annotations

import re
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


# ── Workflow state ────────────────────────────────────────────────────────────

class WorkflowState(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    BUDGET_EXHAUSTED = "budget_exhausted"
    FAILED = "failed"
    TERMINATED = "terminated"
    UNKNOWN = "unknown"

    @classmethod
    def parse(cls, value: Optional[str]) -> "WorkflowState":
        if value is None:
            return cls.UNKNOWN
        normalized = value.lower()
        mapping = {
            "pending": cls.PENDING,
            "running": cls.RUNNING,
            "completed": cls.COMPLETED,
            "succeeded": cls.COMPLETED,
            "success": cls.COMPLETED,
            "budget_exhausted": cls.BUDGET_EXHAUSTED,
            "failed": cls.FAILED,
            "terminated": cls.TERMINATED,
            "cancelled": cls.TERMINATED,
            "timed_out": cls.TERMINATED,
            "timeout": cls.TERMINATED,
        }
        return mapping.get(normalized, cls.UNKNOWN)

    @property
    def is_terminal(self) -> bool:
        return self in (
            WorkflowState.COMPLETED,
            WorkflowState.BUDGET_EXHAUSTED,
            WorkflowState.FAILED,
            WorkflowState.TERMINATED,
        )


TERMINAL_NODES = {
    "success_final",
    "success_original_glb",
    "failed_final",
    "final_latest_valid",
    "final_validated_correction",
    "fail_generation",
}

NODE_PROGRESS_LABELS: Dict[str, str] = {
    "sketch_to_3d_generator": "Generating your 3D model...",
    "caption_prompt": "Reading your reference image...",
    "caption_llm": "Understanding the reference image...",
    "generation_prompt": "Preparing the 3D generation prompt...",
    "code_generation_llm": "Writing the Blender scene...",
    "run_blender": "Building and exporting the 3D model...",
    "blender_retry_gate": "Checking the generated model...",
    "build_repair_prompt": "Preparing an automatic repair...",
    "repair_llm": "Repairing the Blender script...",
    "capture_validation_screenshots": "Capturing validation views...",
    "validation_prompt": "Preparing model validation...",
    "validation_llm": "Reviewing the generated model...",
    "validation_result_parser": "Finalizing the model...",
    "validation_correction_blender": "Applying validation fixes...",
    "final_latest_valid": "Finalizing the model...",
    "final_validated_correction": "Finalizing the corrected model...",
    "fail_generation": "Generation failed.",
    "regenerate_3d_part": "Regenerating the selected part...",
    "add_3d_part": "Adding a new part...",
    "articulate_3d_model": "Articulating your 3D model...",
}


# ── API response models ───────────────────────────────────────────────────────

class WorkflowStartResponse(BaseModel):
    workflow_id: str
    status_url: str
    result_url: str
    projected_cost: int = 0
    authorized_budget: int = 0


class WorkflowStatus(BaseModel):
    workflow_id: str
    state: WorkflowState
    current_node: Optional[str] = None
    last_exit_node: Optional[str] = None

    @property
    def is_terminal_by_node(self) -> bool:
        return (
            self.current_node in TERMINAL_NODES
            or self.last_exit_node in TERMINAL_NODES
        )

    @property
    def is_terminal(self) -> bool:
        return self.state.is_terminal or self.is_terminal_by_node

    @property
    def progress_label(self) -> str:
        node = self.current_node or self.last_exit_node or ""
        return NODE_PROGRESS_LABELS.get(node, "Generating...")

    @classmethod
    def from_api(cls, workflow_id: str, data: Dict[str, Any]) -> "WorkflowStatus":
        runtime = data.get("runtime") or {}
        visit_seq = data.get("node_visit_seq") or {}
        current_node = list(visit_seq.keys())[-1] if visit_seq else None
        return cls(
            workflow_id=workflow_id,
            state=WorkflowState.parse(runtime.get("state")),
            current_node=current_node,
            last_exit_node=runtime.get("last_exit_node_id"),
        )


class GenerationReadiness(BaseModel):
    ready: bool
    reason: Optional[str] = None
    projected_cost: int = 0
    authorized_budget: int = 0

    @property
    def user_message(self) -> str:
        if self.ready:
            return "Generation is ready."
        if self.reason == "generation_service_unavailable":
            return "The generation service is unavailable. Please try again shortly."
        return "Generation is not available right now."


# ── MCP auth/onboarding models ───────────────────────────────────────────────

class MCPStatusIdentity(BaseModel):
    user_id: str
    email: str
    tenant_id: Optional[str] = None


class MCPStatusSession(BaseModel):
    established: bool = False
    expires_at: Optional[str] = None


class MCPStatusCredits(BaseModel):
    balance: int = 0
    reserved: int = 0
    available: int = 0
    funded: bool = False


class MCPStatus(BaseModel):
    authenticated: bool = False
    identity: Optional[MCPStatusIdentity] = None
    mcp_session: MCPStatusSession = Field(default_factory=MCPStatusSession)
    credits: Optional[MCPStatusCredits] = None
    generation_ready: bool = False
    next_action: Optional[str] = None
    next_action_url: Optional[str] = None

    @property
    def is_ready(self) -> bool:
        return self.authenticated and self.generation_ready and self.next_action is None

    @property
    def available_credits(self) -> Optional[int]:
        return self.credits.available if self.credits else None

    @property
    def user_message(self) -> str:
        if self.next_action == "sign_in":
            return "Sign in to Nova3D to continue."
        if self.next_action == "session_expired":
            return "Your Nova3D session expired. Sign in again to continue."
        if self.next_action == "purchase_credits":
            return "Your Nova3D account is connected, but you need credits before generating."
        if self.next_action == "service_unavailable":
            return "Nova3D is temporarily unavailable. Please try again shortly."
        if self.is_ready:
            if self.identity and self.credits:
                return (
                    f"Connected as {self.identity.email}. "
                    f"Credits available: {self.credits.available}."
                )
            return "Nova3D is ready."
        if self.authenticated:
            return "Nova3D is connected, but readiness is still being confirmed."
        return "Nova3D status is unavailable."


class MCPSessionExchange(BaseModel):
    token: str
    expires_at: Optional[str] = None


# ── Generation result ─────────────────────────────────────────────────────────

RESULT_NODE_KEYS = [
    "final_validated_correction",
    "final_latest_valid",
    "sketch_to_3d_generator",
    "regenerate_3d_part",
    "add_3d_part",
    "articulate_3d_model",
    "fail_generation",
]


class GenerationResult(BaseModel):
    glb_url: Optional[str] = None
    model_artifact: Optional[Dict[str, Any]] = None
    code_artifact: Optional[Dict[str, Any]] = None
    joints_artifact: Optional[Dict[str, Any]] = None
    joints: List[Dict[str, Any]] = Field(default_factory=list)
    joint_count: int = 0
    parts: List[str] = Field(default_factory=list)
    operation: Optional[str] = None
    failed: bool = False
    error_message: Optional[str] = None
    error_category: Optional[str] = None
    retryable: bool = False
    api_key_source: Optional[str] = None
    workflow_id: str = ""

    @classmethod
    def from_api(
        cls,
        data: Dict[str, Any],
        workflow_id: str,
    ) -> "GenerationResult":
        payload = _extract_generator_payload(data)
        if payload is None:
            error = _extract_root_error(data)
            return cls(
                failed=True,
                error_message=error or "Generation returned no output.",
                workflow_id=workflow_id,
            )

        unwrapped = _unwrap_result(payload)
        glb_url = _extract_glb_url(unwrapped)
        model_artifact = _extract_map(unwrapped, ["model_artifact", "model", "glb_artifact"])
        code_artifact = _extract_map(
            unwrapped,
            ["code_artifact", "source_code_artifact", "input_code_artifact"],
        )
        joints_artifact = _as_str_map(unwrapped.get("joints_artifact"))
        joints = _extract_joints(unwrapped)
        joint_count = _int_val(unwrapped.get("joint_count")) or len(joints)
        operation = _str_val(unwrapped.get("operation"))
        api_key_source = _str_val(unwrapped.get("api_key_source"))
        parts = _extract_part_names(unwrapped, joints, code_artifact)
        failure = _extract_failure(unwrapped)
        error_message = (failure.get("message") if failure else None) or _extract_root_error(data)
        failed = glb_url is None and (_is_failed(data) or error_message is not None)
        return cls(
            glb_url=glb_url,
            model_artifact=model_artifact,
            code_artifact=code_artifact,
            joints_artifact=joints_artifact,
            joints=joints,
            joint_count=joint_count,
            parts=parts,
            operation=operation,
            failed=failed,
            error_message=error_message,
            error_category=failure.get("category") if failure else None,
            retryable=failure.get("retryable", False) if failure else False,
            api_key_source=api_key_source,
            workflow_id=workflow_id,
        )


# ── Result parsing helpers ────────────────────────────────────────────────────

def _extract_generator_payload(
    data: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    for key in RESULT_NODE_KEYS:
        node = data.get(key)
        if isinstance(node, list) and node:
            first = node[0]
            if isinstance(first, dict):
                return {str(k): v for k, v in first.items()}
    return None


def _unwrap_result(payload: Dict[str, Any]) -> Dict[str, Any]:
    result = _as_str_map(payload.get("result"))
    return result if result is not None else payload


def _extract_glb_url(unwrapped: Dict[str, Any]) -> Optional[str]:
    url = unwrapped.get("model_url")
    if isinstance(url, str) and url.strip():
        return url.strip()
    for key in ["model", "model_artifact", "glb_artifact"]:
        artifact = unwrapped.get(key)
        if isinstance(artifact, dict):
            u = artifact.get("url")
            if isinstance(u, str) and u.strip():
                return u.strip()
    return None


def _extract_map(
    unwrapped: Dict[str, Any], keys: List[str]
) -> Optional[Dict[str, Any]]:
    for key in keys:
        result = _as_str_map(unwrapped.get(key))
        if result is not None:
            return result
    return None


def _extract_joints(unwrapped: Dict[str, Any]) -> List[Dict[str, Any]]:
    raw = unwrapped.get("joints")
    if not isinstance(raw, list):
        return []
    return [
        {str(k): v for k, v in item.items()}
        for item in raw
        if isinstance(item, dict)
    ]


def _extract_part_names(
    unwrapped: Dict[str, Any],
    joints: List[Dict[str, Any]],
    code_artifact: Optional[Dict[str, Any]] = None,
) -> List[str]:
    """Extract named part/mesh identifiers from the result."""
    # 1. API-first: use explicit parts field if the backend returns one
    api_parts = unwrapped.get("parts")
    if isinstance(api_parts, list) and api_parts:
        return [str(p) for p in api_parts if p]

    # 2. Regex over Blender construction script — obj.name = "part_name"
    if isinstance(code_artifact, dict):
        content = code_artifact.get("content") or ""
        if content:
            names = re.findall(r'\.name\s*=\s*["\']([^"\']+)["\']', content)
            if names:
                return list(dict.fromkeys(names))  # deduplicate, preserve order

    # 3. Fallback: extract from joints (articulated assets)
    names = []
    for joint in joints:
        mesh = joint.get("mesh") or joint.get("name")
        if isinstance(mesh, str) and mesh.strip():
            names.append(mesh.strip())
    return list(dict.fromkeys(names))


def _extract_failure(
    unwrapped: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    status = (unwrapped.get("status") or "").lower()
    action = (unwrapped.get("action") or "").lower()
    ok = unwrapped.get("ok")
    failure_map = _as_str_map(unwrapped.get("failure"))

    is_failed = (
        status == "failed"
        or action == "error"
        or ok is False
        or failure_map is not None
        or unwrapped.get("error_category") is not None
        or unwrapped.get("user_message") is not None
    )
    if not is_failed:
        return None

    category = _str_val(
        (failure_map or {}).get("category") or unwrapped.get("error_category")
    )
    provider = _str_val(
        (failure_map or {}).get("provider") or unwrapped.get("provider")
    )
    retryable = bool(
        (failure_map or {}).get("retryable") or unwrapped.get("retryable") or False
    )
    message = (
        _str_val((failure_map or {}).get("user_message"))
        or _str_val((failure_map or {}).get("message"))
        or _str_val(unwrapped.get("user_message"))
        or _str_val(unwrapped.get("message"))
        or _str_val(unwrapped.get("detail"))
        or _str_val(unwrapped.get("error"))
        or _message_for_category(category, provider, retryable)
    )
    return {"message": message, "category": category, "provider": provider, "retryable": retryable}


def _extract_root_error(data: Dict[str, Any]) -> Optional[str]:
    for key in ["error", "detail", "message"]:
        val = data.get(key)
        if val is not None:
            return _str_val(val) or str(val)
    return None


def _is_failed(data: Dict[str, Any]) -> bool:
    state = (data.get("state") or "").lower()
    if state in ("failed", "failure"):
        return True
    runtime = data.get("runtime") or {}
    r_state = (runtime.get("state") or "").lower()
    return r_state in ("failed", "failure", "budget_exhausted")


def _as_str_map(value: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(value, dict):
        return None
    return {str(k): v for k, v in value.items()}


def _str_val(value: Any) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, str):
        return value.strip() or None
    if isinstance(value, dict):
        for key in ("user_message", "message"):
            result = _str_val(value.get(key))
            if result:
                return result
    return str(value)


def _int_val(value: Any) -> Optional[int]:
    if isinstance(value, int):
        return value
    if isinstance(value, (float,)):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return None
    return None


def _message_for_category(
    category: Optional[str],
    provider: Optional[str],
    retryable: bool,
) -> str:
    label = provider if provider else "The selected provider"
    messages = {
        "invalid_api_key": f"The {label} key saved in your Nova3D account is invalid. Update it at https://app.nova3d.xyz/api-key",
        "missing_api_key": f"No {label} key found in your Nova3D account. Add one at https://app.nova3d.xyz/api-key",
        "model_access_denied": f"{label} does not allow this key to use the selected model. Choose another.",
        "unsupported_provider_for_model": f"{label} cannot run the selected model. Choose a compatible pair.",
        "insufficient_credits": f"{label} does not have enough credits for this generation.",
        "quota_or_rate_limit": f"{label} quota or rate limit reached. Wait a bit or switch providers.",
        "provider_unavailable": f"{label} is temporarily unavailable. Retry shortly or switch providers.",
        "api_timeout": f"{label} timed out. Retry or switch providers.",
        "blender_generation_failed": "The generated 3D script could not produce a valid model after repair attempts.",
        "artifact_upload_failed": "The model was generated but the download artifact could not be prepared.",
        "generation_timeout": "Generation took longer than expected. It may still finish — retry if it does not appear.",
    }
    if category and category in messages:
        return messages[category]
    if retryable:
        return "Generation failed. Retry shortly or switch providers."
    return "Generation failed. Try another prompt or model."
