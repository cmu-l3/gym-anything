from __future__ import annotations

from typing import Any


MECHANIC_ID = "impossible_ecology"


def _point(value: Any, width: int, height: int) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError("drag point is malformed")
    if isinstance(value[0], bool) or isinstance(value[1], bool):
        raise ValueError("boolean drag point is invalid")
    x, y = int(value[0]), int(value[1])
    if not (0 <= x <= width and 0 <= y <= height):
        raise ValueError("drag point leaves terrarium stage")
    return x, y


def _inside(point: tuple[int, int], rect: dict[str, Any]) -> bool:
    x, y = point
    left, top = int(rect["x"]), int(rect["y"])
    return left <= x <= left + int(rect["width"]) and top <= y <= top + int(rect["height"])


def _habitat_at(point: tuple[int, int], rects: list[dict[str, Any]]) -> str | None:
    for rect in rects:
        if _inside(point, rect):
            return str(rect.get("id") or "")
    return None


def _cycle_map(ground_truth: dict[str, Any]) -> dict[int, dict[str, Any]]:
    raw = ground_truth.get("cycles")
    if not isinstance(raw, list) or len(raw) != 3:
        raise ValueError("three causal cycles are required")
    output: dict[int, dict[str, Any]] = {}
    for cycle in raw:
        if not isinstance(cycle, dict):
            raise ValueError("cycle is malformed")
        step = int(cycle.get("step"))
        output[step] = cycle
    if set(output) != {0, 1, 2}:
        raise ValueError("cycle steps are incomplete")
    return output


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "ground-truth mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "public-state challenge mismatch"}

    try:
        protocol = [str(item) for item in ground_truth.get("protocol") or []]
        if len(protocol) != 3 or set(protocol) != {"CLIMATE", "FOOD", "LIGHT"}:
            raise ValueError("protocol is invalid")
        ticks_per_cycle = int(ground_truth.get("ticks_per_cycle"))
        if ticks_per_cycle < 6:
            raise ValueError("response cycle is too short")
        cycles = _cycle_map(ground_truth)
        stage = public_state.get("stage") or {}
        width, height = int(stage["width"]), int(stage["height"])
        habitat_rects = [dict(item) for item in ground_truth.get("habitat_rects") or []]
        if len(habitat_rects) != 5:
            raise ValueError("five habitats are required")
        quarantine_rect = dict(ground_truth.get("quarantine_rect") or {})
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid terrarium contract: {exc}"}

    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 500):
        return {"graded": True, "passed": False, "feedback": "causal transcript is missing or outside limits"}

    progress = 0
    active_cycle: dict[str, Any] | None = None
    quarantined_id: str | None = None
    drag: dict[str, Any] | None = None
    current_cycles: list[str] = []
    current_tick_total = 0
    quarantine_moves = 0
    reset_count = 0
    poisoned = False

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")

        if kind == "reset":
            progress = 0
            active_cycle = None
            quarantined_id = None
            drag = None
            current_cycles = []
            current_tick_total = 0
            quarantine_moves = 0
            poisoned = False
            reset_count += 1
            continue

        if kind == "probe_rejected":
            probe = str(event.get("probe") or "")
            if active_cycle is not None or progress >= len(protocol) or probe == protocol[progress]:
                return {"graded": True, "passed": False, "feedback": f"event {sequence} is not a valid rejected probe"}
            poisoned = True
            continue

        if kind == "probe":
            probe = str(event.get("probe") or "")
            if poisoned or active_cycle is not None or progress >= len(protocol):
                return {"graded": True, "passed": False, "feedback": f"event {sequence} starts a probe in an invalid state"}
            if event.get("step") != progress or probe != protocol[progress]:
                return {"graded": True, "passed": False, "feedback": f"event {sequence} violates the posted protocol"}
            active_cycle = {"step": progress, "probe": probe, "next_tick": 1, "elapsed": 0}
            continue

        if kind == "tick":
            if active_cycle is None:
                return {"graded": True, "passed": False, "feedback": f"event {sequence} records a tick without an active probe"}
            step = active_cycle["step"]
            tick = active_cycle["next_tick"]
            if event.get("step") != step or event.get("probe") != active_cycle["probe"] or event.get("tick") != tick:
                return {"graded": True, "passed": False, "feedback": f"event {sequence} response tick is out of order"}
            frames = cycles[step].get("frames") or []
            if len(frames) != ticks_per_cycle or event.get("snapshot") != frames[tick - 1].get("snapshot"):
                return {"graded": True, "passed": False, "feedback": f"event {sequence} response snapshot was tampered"}
            try:
                elapsed = int(event.get("elapsed_ms"))
            except (TypeError, ValueError):
                return {"graded": True, "passed": False, "feedback": f"event {sequence} is missing cycle time"}
            if elapsed < tick * 70 or elapsed < active_cycle["elapsed"]:
                return {"graded": True, "passed": False, "feedback": f"event {sequence} did not wait through the visible response"}
            active_cycle["elapsed"] = elapsed
            active_cycle["next_tick"] += 1
            current_tick_total += 1
            continue

        if kind == "cycle_complete":
            if active_cycle is None or active_cycle["next_tick"] != ticks_per_cycle + 1:
                return {"graded": True, "passed": False, "feedback": f"event {sequence} closes an incomplete response cycle"}
            if event.get("step") != active_cycle["step"] or event.get("probe") != active_cycle["probe"]:
                return {"graded": True, "passed": False, "feedback": f"event {sequence} completes the wrong probe"}
            current_cycles.append(active_cycle["probe"])
            progress += 1
            active_cycle = None
            continue

        if kind in {"quarantine_down", "quarantine_move", "quarantine_up"}:
            try:
                point = _point(event.get("point"), width, height)
            except (TypeError, ValueError) as exc:
                return {"graded": True, "passed": False, "feedback": f"event {sequence}: {exc}"}
            if kind == "quarantine_down":
                if poisoned or active_cycle is not None or progress != len(protocol):
                    return {"graded": True, "passed": False, "feedback": "quarantine began before all causal trials completed"}
                habitat_id = _habitat_at(point, habitat_rects)
                if not habitat_id or event.get("habitat_id") != habitat_id:
                    return {"graded": True, "passed": False, "feedback": "quarantine drag did not begin inside the claimed habitat"}
                drag = {"habitat_id": habitat_id, "moves": 0}
            elif kind == "quarantine_move":
                if drag is None:
                    return {"graded": True, "passed": False, "feedback": "quarantine move has no specimen"}
                drag["moves"] += 1
                quarantine_moves += 1
            else:
                if drag is None or event.get("habitat_id") != drag["habitat_id"]:
                    return {"graded": True, "passed": False, "feedback": "quarantine drop specimen mismatch"}
                quarantined_id = drag["habitat_id"] if _inside(point, quarantine_rect) else None
                drag = None
            continue

        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    expected_scalars = {
        "protocol_progress": progress,
        "quarantined_id": quarantined_id,
        "tick_total": current_tick_total,
        "quarantine_moves": quarantine_moves,
        "reset_count": reset_count,
    }
    for field, expected in expected_scalars.items():
        if payload.get(field) != expected:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} does not match causal replay"}
    if payload.get("completed_cycles") != current_cycles:
        return {"graded": True, "passed": False, "feedback": "submitted completed cycles do not match replay"}

    culprit_id = str(ground_truth.get("culprit_id") or "")
    passed = (
        not poisoned
        and active_cycle is None
        and drag is None
        and progress == 3
        and current_cycles == protocol
        and current_tick_total == 3 * ticks_per_cycle
        and quarantine_moves >= 3
        and quarantined_id == culprit_id
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"causal replay: probes {progress}/3; response ticks {current_tick_total}/{3 * ticks_per_cycle}; "
            f"quarantine={'correct' if quarantined_id == culprit_id else 'incorrect'}; drag samples {quarantine_moves}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "protocol": ground_truth.get("protocol"),
        "culprit_id": ground_truth.get("culprit_id"),
        "anomaly_probe": ground_truth.get("anomaly_probe"),
        "response_law": ground_truth.get("response_law"),
    }
