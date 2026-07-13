from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "wonky_text_hostile_rendering"


def _wrap(value: float) -> float:
    return value % 360.0


def _delta(first: float, second: float) -> float:
    return abs((first - second + 180.0) % 360.0 - 180.0)


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    contract = dict(ground_truth.get("press") or {})
    plates = {str(item["id"]): dict(item) for item in contract.get("plates") or []}
    angles = {plate_id: float(plate["initial"]) for plate_id, plate in plates.items()}
    locked: set[str] = set()
    pressed = False
    events = payload.get("events")
    if not isinstance(events, list) or not 4 <= len(events) <= 100:
        return {"graded": True, "passed": False, "feedback": "registration transcript is missing or outside limits"}
    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind, plate_id = str(event.get("kind") or ""), str(event.get("plate_id") or "")
        if kind == "wheel_drag":
            try:
                drag = float(event.get("delta"))
            except (TypeError, ValueError):
                return {"graded": True, "passed": False, "feedback": "plate drag is invalid"}
            if plate_id not in plates or plate_id in locked or not math.isfinite(drag) or abs(drag) > float(contract["max_drag_delta"]):
                return {"graded": True, "passed": False, "feedback": "plate moved outside the optical wheel contract"}
            angles[plate_id] = _wrap(angles[plate_id] + drag)
            continue
        if kind == "lock":
            if plate_id not in plates or pressed or event.get("locked") is not isinstance(event.get("locked"), bool):
                return {"graded": True, "passed": False, "feedback": "plate lock is invalid"}
            if event["locked"]:
                locked.add(plate_id)
            else:
                locked.discard(plate_id)
            continue
        if kind == "press":
            if pressed or locked != set(plates):
                return {"graded": True, "passed": False, "feedback": "press descended before all physical locks engaged"}
            pressed = True
            continue
        return {"graded": True, "passed": False, "feedback": f"unknown registration event {kind}"}
    errors = {plate_id: _delta(angles[plate_id], float(plate["target"])) for plate_id, plate in plates.items()}
    passed = pressed and all(error <= float(contract["tolerance"]) for error in errors.values())
    return {"graded": True, "passed": passed, "feedback": "plate registration " + ", ".join(f"{plate_id}={error:.2f}°" for plate_id, error in errors.items())}
