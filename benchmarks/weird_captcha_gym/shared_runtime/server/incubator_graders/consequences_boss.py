from __future__ import annotations

from typing import Any


MECHANIC_ID = "consequences_boss"


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    events = payload.get("events")
    if not isinstance(events, list) or not 12 <= len(events) <= 80:
        return {"graded": True, "passed": False, "feedback": "covenant transcript is missing or outside limits"}
    scene_ids = [str(item) for item in ground_truth.get("scene_ids") or []]
    boss_order = [str(item) for item in ground_truth.get("boss_order") or []]
    commitments: dict[str, tuple[str, int]] = {}
    reconstructions: list[str] = []
    storm_seen = False
    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind in {"place", "seal"}:
            if str(event.get("scene_id") or "") not in scene_ids:
                return {"graded": True, "passed": False, "feedback": "unknown covenant scene"}
            continue
        if kind == "commit":
            scene_id = str(event.get("scene_id") or "")
            if storm_seen or len(commitments) >= len(scene_ids) or scene_id != scene_ids[len(commitments)]:
                return {"graded": True, "passed": False, "feedback": "commitment order is invalid"}
            socket, seal = str(event.get("socket") or ""), event.get("seal")
            if socket not in {"left", "right"} or not isinstance(seal, int) or not 0 <= seal <= 3 or scene_id in commitments:
                return {"graded": True, "passed": False, "feedback": "commitment state is invalid"}
            commitments[scene_id] = (socket, seal)
            continue
        if kind == "storm":
            if storm_seen or len(commitments) != len(scene_ids) or int(event.get("duration_ms") or 0) < int(ground_truth.get("storm_ms") or 0):
                return {"graded": True, "passed": False, "feedback": "ledger transition is invalid"}
            storm_seen = True
            continue
        if kind == "reconstruct":
            if not storm_seen or len(reconstructions) >= len(boss_order):
                return {"graded": True, "passed": False, "feedback": "reconstruction began outside judgment"}
            scene_id = str(event.get("scene_id") or "")
            if scene_id != boss_order[len(reconstructions)]:
                return {"graded": True, "passed": False, "feedback": "judgment order was not followed"}
            answer = (str(event.get("socket") or ""), event.get("seal"))
            if answer != commitments.get(scene_id):
                return {"graded": True, "passed": False, "feedback": "a covenant was reconstructed incorrectly"}
            reconstructions.append(scene_id)
            continue
        return {"graded": True, "passed": False, "feedback": f"unknown covenant event {kind}"}
    passed = storm_seen and len(commitments) == len(scene_ids) and reconstructions == boss_order
    return {"graded": True, "passed": passed, "feedback": f"covenants reconstructed {len(reconstructions)}/{len(scene_ids)} after occlusion"}
