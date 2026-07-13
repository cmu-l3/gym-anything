from __future__ import annotations

from typing import Any


MECHANIC_ID = "rorschach_fixed_rubric"


def _point(value: Any, width: int, height: int) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2 or any(isinstance(item, bool) for item in value):
        raise ValueError("stamp point is malformed")
    x, y = int(value[0]), int(value[1])
    if not (0 <= x <= width and 0 <= y <= height):
        raise ValueError("stamp point leaves material stage")
    return x, y


def _inside(point: tuple[int, int], rect: dict[str, Any]) -> bool:
    return (
        int(rect["x"]) <= point[0] <= int(rect["x"]) + int(rect["width"])
        and int(rect["y"]) <= point[1] <= int(rect["y"]) + int(rect["height"])
    )


def _blot_at(point: tuple[int, int], rects: list[dict[str, Any]]) -> str | None:
    for rect in rects:
        if _inside(point, rect):
            return str(rect.get("id") or "")
    return None


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
        if len(protocol) != 3 or set(protocol) != {"FOLD", "PRESSURE", "COOL"}:
            raise ValueError("material protocol is invalid")
        cycles = {int(item["step"]): dict(item) for item in ground_truth.get("cycles") or []}
        if set(cycles) != {0, 1, 2}:
            raise ValueError("material cycles are incomplete")
        ticks_per_cycle = int(ground_truth.get("ticks_per_cycle"))
        stage = ground_truth.get("stage") or {}
        width, height = int(stage["width"]), int(stage["height"])
        blot_rects = [dict(item) for item in ground_truth.get("blot_rects") or []]
        stamp_dock = dict(ground_truth.get("stamp_dock_rect") or {})
        fold_min_distance = int(ground_truth.get("fold_min_distance"))
        pressure_min_ms = int(ground_truth.get("pressure_min_ms"))
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid material contract: {exc}"}
    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 600):
        return {"graded": True, "passed": False, "feedback": "material transcript is missing or outside limits"}

    progress = 0
    active_cycle: dict[str, Any] | None = None
    ready_tool: str | None = None
    fold: dict[str, Any] | None = None
    pressure_down = False
    stamp: dict[str, Any] | None = None
    stamped_id: str | None = None
    poisoned = False
    completed_tools: list[str] = []
    tick_total = 0
    fold_samples = pressure_holds = thermal_pulses = stamp_moves = reset_count = 0

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind == "reset":
            progress = 0
            active_cycle = ready_tool = fold = stamp = None
            pressure_down = False
            stamped_id = None
            poisoned = False
            completed_tools = []
            tick_total = fold_samples = pressure_holds = thermal_pulses = stamp_moves = 0
            reset_count += 1
            continue
        if kind == "tool_rejected":
            tool = str(event.get("tool") or "")
            if active_cycle is not None or progress >= 3 or tool == protocol[progress]:
                return {"graded": True, "passed": False, "feedback": "tool rejection event is inconsistent"}
            poisoned = True
            continue
        if poisoned:
            return {"graded": True, "passed": False, "feedback": "contaminated material run was not reset"}

        if kind == "fold_start":
            value = int(event.get("value"))
            if active_cycle is not None or fold is not None or value > 35:
                return {"graded": True, "passed": False, "feedback": "fold gesture did not begin at the axis origin"}
            fold = {"start": value, "last": value, "moves": 0}
            continue
        if kind == "fold_move":
            value = int(event.get("value"))
            if fold is None or not 0 <= value <= 300 or value < fold["last"]:
                return {"graded": True, "passed": False, "feedback": "fold axis motion is invalid"}
            fold["last"] = value
            fold["moves"] += 1
            fold_samples += 1
            continue
        if kind == "fold_end":
            value = int(event.get("value"))
            if fold is None or value != fold["last"] or fold["moves"] < 3 or value - fold["start"] < fold_min_distance:
                return {"graded": True, "passed": False, "feedback": "fold axis was not physically swept far enough"}
            if protocol[progress] != "FOLD":
                return {"graded": True, "passed": False, "feedback": "fold tool was used out of protocol order"}
            ready_tool = "FOLD"
            fold = None
            continue
        if kind == "fold_cancel":
            value = int(event.get("value"))
            if fold is None or value != fold["last"] or value - fold["start"] >= fold_min_distance:
                return {"graded": True, "passed": False, "feedback": "cancelled fold gesture is inconsistent"}
            fold = None
            poisoned = True
            continue
        if kind == "pressure_down":
            if active_cycle is not None or pressure_down:
                return {"graded": True, "passed": False, "feedback": "pressure hold overlaps another tool"}
            pressure_down = True
            continue
        if kind == "pressure_up":
            duration = int(event.get("duration_ms"))
            if not pressure_down or duration < pressure_min_ms or duration > 5_000:
                return {"graded": True, "passed": False, "feedback": "pressure hold duration is outside the physical window"}
            if protocol[progress] != "PRESSURE":
                return {"graded": True, "passed": False, "feedback": "pressure tool was used out of protocol order"}
            pressure_down = False
            pressure_holds += 1
            ready_tool = "PRESSURE"
            continue
        if kind == "pressure_cancel":
            duration = int(event.get("duration_ms"))
            if not pressure_down or duration < 0 or duration >= pressure_min_ms:
                return {"graded": True, "passed": False, "feedback": "cancelled pressure gesture is inconsistent"}
            pressure_down = False
            poisoned = True
            continue
        if kind == "thermal_pulse":
            if active_cycle is not None or protocol[progress] != "COOL":
                return {"graded": True, "passed": False, "feedback": "cooling pulse was used out of protocol order"}
            thermal_pulses += 1
            ready_tool = "COOL"
            continue
        if kind == "probe":
            tool = str(event.get("tool") or "")
            if active_cycle is not None or ready_tool != tool or event.get("step") != progress or tool != protocol[progress]:
                return {"graded": True, "passed": False, "feedback": "material probe does not follow its physical gesture"}
            active_cycle = {"tool": tool, "step": progress, "next_tick": 1, "elapsed": 0}
            ready_tool = None
            continue
        if kind == "tick":
            if active_cycle is None:
                return {"graded": True, "passed": False, "feedback": "response sample has no active material probe"}
            tick = active_cycle["next_tick"]
            if event.get("step") != active_cycle["step"] or event.get("tool") != active_cycle["tool"] or event.get("tick") != tick:
                return {"graded": True, "passed": False, "feedback": "material response sample is out of order"}
            frames = cycles[active_cycle["step"]].get("frames") or []
            if len(frames) != ticks_per_cycle or event.get("snapshot") != frames[tick - 1].get("snapshot"):
                return {"graded": True, "passed": False, "feedback": "material response sample was tampered"}
            elapsed = int(event.get("elapsed_ms"))
            if elapsed < tick * 65 or elapsed < active_cycle["elapsed"]:
                return {"graded": True, "passed": False, "feedback": "transient response was not observed long enough"}
            active_cycle["elapsed"] = elapsed
            active_cycle["next_tick"] += 1
            tick_total += 1
            continue
        if kind == "cycle_complete":
            if active_cycle is None or active_cycle["next_tick"] != ticks_per_cycle + 1 or event.get("tool") != active_cycle["tool"]:
                return {"graded": True, "passed": False, "feedback": "material cycle completed early or for the wrong tool"}
            completed_tools.append(active_cycle["tool"])
            progress += 1
            active_cycle = None
            continue
        if kind in {"stamp_down", "stamp_move", "stamp_up"}:
            try:
                point = _point(event.get("point"), width, height)
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            if kind == "stamp_down":
                if active_cycle is not None or progress != 3 or not _inside(point, stamp_dock):
                    return {"graded": True, "passed": False, "feedback": "stamp did not leave its dock after all probes"}
                stamp = {"moves": 0}
            elif kind == "stamp_move":
                if stamp is None:
                    return {"graded": True, "passed": False, "feedback": "stamp move has no physical stamp"}
                stamp["moves"] += 1
                stamp_moves += 1
            else:
                if stamp is None or stamp["moves"] < 3:
                    return {"graded": True, "passed": False, "feedback": "stamp was not physically dragged"}
                stamped_id = _blot_at(point, blot_rects)
                stamp = None
            continue
        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    expected = {
        "protocol_progress": progress,
        "completed_tools": completed_tools,
        "tick_total": tick_total,
        "fold_samples": fold_samples,
        "pressure_holds": pressure_holds,
        "thermal_pulses": thermal_pulses,
        "stamp_moves": stamp_moves,
        "stamped_id": stamped_id,
        "reset_count": reset_count,
    }
    for field, value in expected.items():
        if payload.get(field) != value:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} does not match material replay"}
    culprit_id = str(ground_truth.get("culprit_id") or "")
    passed = (
        not poisoned
        and active_cycle is None
        and ready_tool is None
        and fold is None
        and not pressure_down
        and stamp is None
        and progress == 3
        and completed_tools == protocol
        and tick_total == 3 * ticks_per_cycle
        and fold_samples >= 3
        and pressure_holds == 1
        and thermal_pulses == 1
        and stamp_moves >= 3
        and stamped_id == culprit_id
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"material replay: tools {progress}/3; response samples {tick_total}/{3 * ticks_per_cycle}; "
            f"fold samples {fold_samples}; pressure holds {pressure_holds}; cooling pulses {thermal_pulses}; "
            f"stamp={'correct' if stamped_id == culprit_id else 'incorrect'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "protocol": ground_truth.get("protocol"),
        "culprit_id": ground_truth.get("culprit_id"),
        "signature": ground_truth.get("signature"),
    }
