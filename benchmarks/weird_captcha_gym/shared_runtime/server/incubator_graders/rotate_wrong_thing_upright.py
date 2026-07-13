from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "rotate_wrong_thing_upright"


def _wrap(value: float) -> float:
    return ((value + 180.0) % 360.0) - 180.0


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    contract = dict(ground_truth.get("gimbal") or {})
    angles = {key: float(value) for key, value in dict(contract.get("initial") or {}).items()}
    target = {key: float(value) for key, value in dict(contract.get("target") or {}).items()}
    coupling = dict(contract.get("coupling") or {})
    views: set[str] = set()
    events = payload.get("events")
    if not isinstance(events, list) or not 3 <= len(events) <= 120:
        return {"graded": True, "passed": False, "feedback": "gimbal transcript is missing or outside limits"}
    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind == "view":
            view = str(event.get("view") or "")
            if view not in set(contract.get("views") or []):
                return {"graded": True, "passed": False, "feedback": "unknown gimbal view"}
            views.add(view)
            continue
        if kind == "drag":
            axis = str(event.get("axis") or "")
            try:
                delta = float(event.get("delta"))
            except (TypeError, ValueError):
                return {"graded": True, "passed": False, "feedback": "gimbal drag is invalid"}
            if axis not in angles or not math.isfinite(delta) or abs(delta) > float(contract.get("max_drag_delta") or 180):
                return {"graded": True, "passed": False, "feedback": "gimbal drag exceeded physical limits"}
            angles[axis] = _wrap(angles[axis] + delta)
            if axis == "outer":
                angles["inner"] = _wrap(angles["inner"] + delta * float(coupling["outer_to_inner"]))
            elif axis == "middle":
                angles["outer"] = _wrap(angles["outer"] + delta * float(coupling["middle_to_outer"]))
            else:
                angles["middle"] = _wrap(angles["middle"] + delta * float(coupling["inner_to_middle"]))
            continue
        return {"graded": True, "passed": False, "feedback": f"unknown gimbal event {kind}"}
    errors = {axis: abs(_wrap(angles[axis] - target[axis])) for axis in target}
    tolerance = float(contract.get("tolerance") or 6)
    passed = set(contract.get("views") or []) <= views and all(error <= tolerance for error in errors.values())
    return {"graded": True, "passed": passed, "feedback": "tri-view gimbal error " + ", ".join(f"{axis}={error:.2f}°" for axis, error in errors.items())}
