from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "reload_interruption"


def _spark(spec: dict[str, Any], elapsed_ms: float) -> tuple[float, float]:
    angle = float(spec["phase"]) + elapsed_ms * float(spec["rate"])
    return (
        float(spec["center"][0]) + math.cos(angle) * float(spec["radius_x"]),
        float(spec["center"][1]) + math.sin(angle) * float(spec["radius_y"]),
    )


def _validate_interrupt(event: dict[str, Any], spec: dict[str, Any]) -> str | None:
    samples = event.get("samples")
    try:
        duration = int(event.get("duration_ms"))
    except (TypeError, ValueError):
        return "overload duration is invalid"
    if duration < int(spec["hold_ms"]) or not isinstance(samples, list) or len(samples) < int(spec["min_samples"]) or len(samples) > 120:
        return "overload hold was too short or sparse"
    clean: list[tuple[int, tuple[float, float]]] = []
    for sample in samples:
        if not isinstance(sample, dict):
            return "overload sample is malformed"
        try:
            elapsed = int(sample["elapsed_ms"])
            point = sample["point"]
            x, y = float(point[0]), float(point[1])
        except (KeyError, TypeError, ValueError, IndexError):
            return "overload sample is malformed"
        if elapsed < 0 or not math.isfinite(x) or not math.isfinite(y):
            return "overload sample is not finite"
        if clean and (elapsed <= clean[-1][0] or elapsed - clean[-1][0] > int(spec["max_gap_ms"])):
            return "overload tracking samples are not continuous"
        clean.append((elapsed, (x, y)))
    # Pointer-down can happen after the overlay appears. Infer that visible path
    # offset from the first physical sample, then validate every later sample.
    first_elapsed, first_point = clean[0]
    center_x, center_y = float(spec["center"][0]), float(spec["center"][1])
    normalized_angle = math.atan2((first_point[1] - center_y) / float(spec["radius_y"]), (first_point[0] - center_x) / float(spec["radius_x"]))
    base_offset = (normalized_angle - float(spec["phase"])) / float(spec["rate"]) - first_elapsed
    tolerance = float(spec["tolerance"])
    for elapsed, point in clean:
        expected = _spark(spec, elapsed + base_offset)
        if math.hypot(point[0] - expected[0], point[1] - expected[1]) > tolerance:
            return "pointer left the moving overload spark"
    if duration - clean[-1][0] > int(spec["max_gap_ms"]) + 90:
        return "overload tracking ended with an unobserved hold gap"
    return None


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    events = payload.get("events")
    if not isinstance(events, list) or not 9 <= len(events) <= 24:
        return {"graded": True, "passed": False, "feedback": "reload transcript is missing or outside limits"}
    expected = [str(item) for item in ground_truth.get("sequence") or []]
    interrupts = {str(item["id"]): dict(item) for item in ground_truth.get("interruptions") or []}
    gestures: list[str] = []
    cleared: list[str] = []
    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind == "abort":
            return {"graded": True, "passed": False, "feedback": "reload was aborted"}
        if kind == "gesture":
            if len(gestures) >= len(expected) or event.get("index") != len(gestures):
                return {"graded": True, "passed": False, "feedback": "gesture index is invalid"}
            direction = str(event.get("direction") or "")
            if direction != expected[len(gestures)]:
                return {"graded": True, "passed": False, "feedback": "remembered gesture was wrong"}
            required_before = [item for item in interrupts.values() if int(item["after_step"]) < len(gestures) + 1]
            if any(item["id"] not in cleared for item in required_before):
                return {"graded": True, "passed": False, "feedback": "reload resumed before clearing an interruption"}
            gestures.append(direction)
            continue
        if kind == "interrupt":
            interrupt_id = str(event.get("interruption_id") or "")
            spec = interrupts.get(interrupt_id)
            if spec is None or interrupt_id in cleared or len(gestures) != int(spec["after_step"]):
                return {"graded": True, "passed": False, "feedback": "overload occurred at the wrong reload state"}
            error = _validate_interrupt(event, spec)
            if error:
                return {"graded": True, "passed": False, "feedback": error}
            cleared.append(interrupt_id)
            continue
        return {"graded": True, "passed": False, "feedback": f"unknown reload event {kind}"}
    passed = gestures == expected and set(cleared) == set(interrupts)
    return {"graded": True, "passed": passed, "feedback": f"remembered gestures {len(gestures)}/{len(expected)}; overload holds {len(cleared)}/{len(interrupts)}"}
