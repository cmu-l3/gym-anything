from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "occlusion_shell_swindle"


def _fail(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _circle_inside(point: dict[str, Any], rect: dict[str, Any], radius: int) -> bool:
    return int(point["x"]) - radius >= int(rect["x"]) and int(point["x"]) + radius <= int(rect["x"]) + int(rect["width"]) and int(point["y"]) - radius >= int(rect["y"]) and int(point["y"]) + radius <= int(rect["y"]) + int(rect["height"])


def _public_round(round_state: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in round_state.items() if key not in {"handoff", "final_carrier"}}


def _validate_round(round_state: dict[str, Any], radius: int) -> None:
    handoff = dict(round_state["handoff"])
    inspection = dict(round_state["inspection"])
    occluder = next((item for item in round_state["occluders"] if item["id"] == handoff["occluder_id"]), None)
    if not occluder or inspection["occluder_id"] != handoff["occluder_id"]:
        raise ValueError("inspection port is not bound to the physical cover")
    if inspection["from_shell"] != handoff["from_shell"] or inspection["partner_shell"] != handoff["partner_shell"] or inspection["to_shell"] != handoff["to_shell"]:
        raise ValueError("visible shuttle differs from the hidden carrier contract")
    if int(inspection["window_start"]) != int(handoff["window_start"]) or int(inspection["window_end"]) != int(handoff["window_end"]):
        raise ValueError("inspection window differs from the occluded passage")
    for tick in range(int(handoff["window_start"]), int(handoff["window_end"]) + 1):
        shells = {item["id"]: item for item in round_state["frames"][tick - 1]["shells"]}
        for shell_id in (handoff["from_shell"], handoff["partner_shell"]):
            if not _circle_inside(shells[shell_id], occluder, radius):
                raise ValueError("paired shell leaves the cover during shuttle inspection")
    expected_final = handoff["to_shell"] if handoff["transfers"] else handoff["from_shell"]
    if expected_final != round_state["final_carrier"] or handoff["to_shell"] != expected_final:
        raise ValueError("final carrier does not follow the visible shuttle")


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge = str(ground_truth.get("challenge_id") or "")
    if any(str(item.get("mechanic_id") or "") != MECHANIC_ID for item in (payload, ground_truth, public_state)):
        return _fail("mechanic mismatch")
    if not challenge or str(payload.get("challenge_id") or "") != challenge or str(public_state.get("challenge_id") or "") != challenge:
        return _fail("stale shell challenge")
    try:
        radius = int(ground_truth["shell_radius"])
        rounds = [dict(item) for item in ground_truth["rounds"]]
        if len(rounds) != 3 or public_state.get("rounds") != [_public_round(item) for item in rounds]:
            raise ValueError("three public tracking rounds differ from the replay contract")
        for round_state in rounds:
            if len(round_state["frames"]) != int(round_state["frame_count"]):
                raise ValueError("tracking frames are incomplete")
            _validate_round(round_state, radius)
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid observable-shell contract: {exc}")
    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 1200):
        return _fail("tracking transcript is missing or outside limits")

    round_index = 0
    active: dict[str, Any] | None = None
    choices: list[dict[str, Any]] = []
    total_ticks = observed_ms = inspection_samples = rewind_count = 0
    attempt_counts = [0, 0, 0]

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return _fail(f"event {sequence} sequence mismatch")
        kind = str(event.get("kind") or "")
        if round_index >= len(rounds):
            return _fail("interaction continued after all tracking rounds")
        current = rounds[round_index]
        if kind == "round_start":
            if active is not None or event.get("round") != round_index:
                return _fail("tracking round start is out of order")
            attempt_counts[round_index] += 1
            active = {"next_tick": 1, "last_elapsed": 0, "stopped": False, "carrier": str(current["initial_carrier"]), "inspection_ticks": set()}
            continue
        if kind == "round_tick":
            if active is None or active["stopped"] or event.get("round") != round_index or event.get("tick") != active["next_tick"]:
                return _fail("tracking frame is out of order")
            tick = active["next_tick"]
            if event.get("shells") != current["frames"][tick - 1]["shells"]:
                return _fail(f"round {round_index + 1} frame {tick} was tampered")
            try:
                elapsed = int(event.get("elapsed_ms"))
            except (TypeError, ValueError):
                return _fail("tracking frame has invalid elapsed time")
            minimum = int(current["preview_ms"]) + tick * max(75, int(current["tick_ms"]) - 35)
            if elapsed < minimum or elapsed < active["last_elapsed"]:
                return _fail("shuffle was not observed for its full physical timeline")
            handoff = current["handoff"]
            if tick == int(handoff["tick"]):
                if active["carrier"] != str(handoff["from_shell"]):
                    return _fail("shuttle source disagrees with tracked carrier")
                active["carrier"] = str(handoff["to_shell"])
            active["next_tick"] += 1
            active["last_elapsed"] = elapsed
            total_ticks += 1
            continue
        if kind == "inspection_sample":
            if active is None or active["stopped"] or event.get("round") != round_index:
                return _fail("peephole sample occurs outside an active shuffle")
            inspection = current["inspection"]
            tick = int(event.get("tick"))
            if tick != active["next_tick"] - 1 or not int(inspection["window_start"]) <= tick <= int(inspection["window_end"]) or tick in active["inspection_ticks"]:
                return _fail("peephole sample is outside the physical shuttle window")
            point = event.get("point")
            if not isinstance(point, list) or len(point) != 2 or any(isinstance(value, bool) or not isinstance(value, (int, float)) for value in point):
                return _fail("peephole sample point is malformed")
            if math.hypot(float(point[0]) - float(inspection["port"][0]), float(point[1]) - float(inspection["port"][1])) > float(inspection["radius"]):
                return _fail("peephole sample misses the visible port")
            if str(event.get("from_shell") or "") != str(inspection["from_shell"]) or str(event.get("to_shell") or "") != str(inspection["to_shell"]):
                return _fail("peephole sample fabricates shuttle engraving")
            active["inspection_ticks"].add(tick)
            inspection_samples += 1
            continue
        if kind == "round_stop":
            if active is None or active["stopped"] or event.get("round") != round_index or active["next_tick"] != int(current["frame_count"]) + 1:
                return _fail("round stopped before every animation frame")
            try:
                elapsed = int(event.get("elapsed_ms"))
            except (TypeError, ValueError):
                return _fail("round stop has invalid elapsed time")
            if elapsed < int(current["preview_ms"]) + int(current["duration_ms"]) * 9 // 10 or elapsed < active["last_elapsed"]:
                return _fail("round stop lacks full observation time")
            active["stopped"] = True
            active["last_elapsed"] = elapsed
            observed_ms += elapsed
            continue
        if kind == "round_rewind":
            if active is None or not active["stopped"] or event.get("round") != round_index or len(active["inspection_ticks"]) >= int(current["inspection"]["minimum_samples"]):
                return _fail("round rewind is not a recovery from a missed peephole")
            active = None
            rewind_count += 1
            continue
        if kind == "round_select":
            shell_id = str(event.get("shell_id") or "")
            if active is None or not active["stopped"] or event.get("round") != round_index or shell_id not in current["shell_ids"]:
                return _fail("shell selection is invalid or premature")
            if len(active["inspection_ticks"]) < int(current["inspection"]["minimum_samples"]):
                return _fail("shell selection lacks a physical peephole observation")
            if active["carrier"] != str(current["final_carrier"]) or shell_id != active["carrier"]:
                return _fail("selected shell disagrees with path plus shuttle replay")
            choices.append({"round": round_index, "shell_id": shell_id})
            active = None
            round_index += 1
            continue
        return _fail(f"event {sequence} has unknown kind {kind!r}")

    expected = {"choices": choices, "total_ticks": total_ticks, "observed_ms": observed_ms, "rounds_completed": round_index, "inspection_samples": inspection_samples, "rewind_count": rewind_count}
    for field, value in expected.items():
        if payload.get(field) != value:
            return _fail(f"submitted {field} does not match shell replay")
    passed = round_index == 3 and active is None and len(choices) == 3 and inspection_samples >= sum(int(item["inspection"]["minimum_samples"]) for item in rounds)
    return {"graded": True, "passed": passed, "score": 100 if passed else 0, "feedback": f"observable shell replay: rounds {round_index}/3; attempts {sum(attempt_counts)}; frames {total_ticks}; peephole samples {inspection_samples}; rewinds {rewind_count}; observation {observed_ms} ms"}


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"rounds": [{"round": index, "initial_carrier": item.get("initial_carrier"), "inspection": item.get("inspection"), "final_carrier": item.get("final_carrier")} for index, item in enumerate(ground_truth.get("rounds") or [])]}
