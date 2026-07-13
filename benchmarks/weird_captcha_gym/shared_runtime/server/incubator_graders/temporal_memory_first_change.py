from __future__ import annotations

from typing import Any


MECHANIC_ID = "temporal_memory_first_change"


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    expected = str(ground_truth.get("target_object_id") or "")
    selected = str(payload.get("selected_object_id") or "")
    passed = bool(expected) and selected == expected
    return {"graded": True, "passed": passed, "feedback": "first transient carrier recovered" if passed else "selected carrier was not the first transient"}
