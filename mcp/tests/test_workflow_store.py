"""Tests for the file-backed per-workflow context store."""
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import pytest

from nova3d_mcp.workflow_store import WorkflowStore, WORKFLOW_TTL_SECONDS


@pytest.fixture
def store(tmp_path):
    return WorkflowStore(path=tmp_path / "mcp-workflows.json")


def test_put_then_get_round_trips(store):
    store.put(
        "wf-1",
        operation="generate",
        conversation_id="conv-1",
        prompt="a chair",
        description=None,
        title="a chair",
        model_option_id="opt-gemini",
    )
    entry = store.get("wf-1")
    assert entry is not None
    assert entry["operation"] == "generate"
    assert entry["conversation_id"] == "conv-1"
    assert entry["prompt"] == "a chair"
    assert entry["title"] == "a chair"
    assert entry["model_option_id"] == "opt-gemini"
    assert entry["completed"] is False
    assert entry["result_payload"] is None
    assert "created_at" in entry


def test_get_unknown_returns_none(store):
    assert store.get("nope") is None


def test_complete_marks_and_caches_payload(store):
    store.put(
        "wf-2",
        operation="regenerate_part",
        conversation_id=None,
        prompt=None,
        description="glass door",
        title=None,
        model_option_id="opt-gemini",
    )
    store.complete("wf-2", {"glb_url": "https://x/y.glb", "failed": False})
    entry = store.get("wf-2")
    assert entry["completed"] is True
    assert entry["result_payload"]["glb_url"] == "https://x/y.glb"


def test_complete_unknown_is_noop(store):
    store.complete("ghost", {"failed": False})
    assert store.get("ghost") is None


def test_persists_across_instances(tmp_path):
    path = tmp_path / "mcp-workflows.json"
    WorkflowStore(path=path).put(
        "wf-3",
        operation="generate",
        conversation_id="c",
        prompt="p",
        description=None,
        title="p",
        model_option_id="o",
    )
    reopened = WorkflowStore(path=path).get("wf-3")
    assert reopened is not None
    assert reopened["operation"] == "generate"


def test_expired_entries_are_pruned(tmp_path):
    path = tmp_path / "mcp-workflows.json"
    store = WorkflowStore(path=path)
    store.put(
        "wf-old",
        operation="generate",
        conversation_id="c",
        prompt="p",
        description=None,
        title="p",
        model_option_id="o",
    )
    # Backdate created_at beyond the TTL by editing the file directly.
    raw = json.loads(path.read_text(encoding="utf-8"))
    stale = datetime.now(timezone.utc) - timedelta(seconds=WORKFLOW_TTL_SECONDS + 60)
    raw["workflows"]["wf-old"]["created_at"] = stale.isoformat()
    path.write_text(json.dumps(raw), encoding="utf-8")

    assert store.get("wf-old") is None
    # Pruned from disk, not just hidden.
    raw_after = json.loads(path.read_text(encoding="utf-8"))
    assert "wf-old" not in raw_after["workflows"]


def test_corrupt_file_is_tolerated(tmp_path):
    path = tmp_path / "mcp-workflows.json"
    path.write_text("not json{", encoding="utf-8")
    store = WorkflowStore(path=path)
    assert store.get("anything") is None
    store.put(
        "wf-ok",
        operation="generate",
        conversation_id="c",
        prompt="p",
        description=None,
        title="p",
        model_option_id="o",
    )
    assert store.get("wf-ok") is not None
