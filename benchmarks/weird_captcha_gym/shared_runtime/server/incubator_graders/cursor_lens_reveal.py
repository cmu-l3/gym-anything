from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "cursor_lens_reveal"


def _fail(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{label} is not finite")
    return float(value)


def _point(value: Any, width: int, height: int, label: str) -> tuple[float, float]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{label} is malformed")
    point = _number(value[0], f"{label} x"), _number(value[1], f"{label} y")
    if not 0 <= point[0] <= width or not 0 <= point[1] <= height:
        raise ValueError(f"{label} leaves the plate")
    return point


def _position(node: dict[str, Any], elapsed_ms: float) -> tuple[float, float]:
    motion = node["motion"]
    phase = float(motion["phase"])
    angle = math.tau * elapsed_ms / float(motion["period_ms"]) + phase
    return (
        float(node["base"][0]) + float(motion["radius_x"]) * math.sin(angle),
        float(node["base"][1]) + float(motion["radius_y"]) * math.cos(angle * float(motion["ratio"])),
    )


def _polarization_error(first: float, second: float) -> float:
    return abs((first - second + 90.0) % 180.0 - 90.0)


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge = str(ground_truth.get("challenge_id") or "")
    task_id = str(ground_truth.get("task_id") or "")
    if any(str(item.get("mechanic_id") or "") != MECHANIC_ID for item in (payload, ground_truth, public_state)):
        return _fail("mechanic mismatch")
    if not challenge or str(payload.get("challenge_id") or "") != challenge or str(public_state.get("challenge_id") or "") != challenge:
        return _fail("stale palimpsest challenge")
    if not task_id or str(payload.get("task_id") or "") != task_id or str(public_state.get("task_id") or "") != task_id:
        return _fail("task identity mismatch")
    try:
        stage = dict(ground_truth["stage"])
        width, height = int(stage["width"]), int(stage["height"])
        nodes = [dict(item) for item in ground_truth["nodes"]]
        requirements = dict(ground_truth["requirements"])
        if len(nodes) != 5 or [int(node["sequence"]) for node in nodes] != list(range(5)):
            raise ValueError("ordered echo contract is incomplete")
        for key in ("stage", "nodes", "clutter", "requirements"):
            if public_state.get(key) != ground_truth.get(key):
                raise ValueError(f"public {key} differs from replay contract")
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid palimpsest contract: {exc}")

    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 2200):
        return _fail("palimpsest transcript is missing or outside limits")
    polarization = 0
    tuning_changes = 0
    probes = 0
    cells: set[str] = set()
    locked_ids: list[str] = []
    current = 0
    hold: dict[str, Any] | None = None
    misses = reset_count = seal_count = 0
    last_time = -1.0

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return _fail(f"event {sequence} has invalid sequence")
        kind = str(event.get("kind") or "")
        try:
            event_time = _number(event.get("t_ms"), "event time")
            if event_time < last_time or event_time > float(requirements["maximum_event_time_ms"]):
                return _fail(f"event {sequence} has impossible time")
            last_time = event_time
            if kind == "tune":
                if hold is not None:
                    return _fail(f"event {sequence} tunes during a capture hold")
                before = int(_number(event.get("from_deg"), "old polarization")) % 180
                after = int(_number(event.get("to_deg"), "new polarization")) % 180
                delta = int(_number(event.get("delta_deg"), "polarization delta"))
                if before != polarization or delta not in (-45, 45) or after != (before + delta) % 180:
                    return _fail(f"event {sequence} reports a false lens turn")
                polarization = after
                tuning_changes += 1
            elif kind == "lens_probe":
                if hold is not None:
                    return _fail(f"event {sequence} probes during a capture hold")
                point = _point(event.get("point"), width, height, "lens probe")
                if int(event.get("polarization_deg")) % 180 != polarization:
                    return _fail(f"event {sequence} reports stale polarization")
                probes += 1
                cells.add(f"{int(point[0] // 58)}:{int(point[1] // 58)}")
            elif kind == "lock_start":
                if hold is not None or current >= len(nodes):
                    return _fail(f"event {sequence} starts an impossible echo hold")
                node = nodes[current]
                point = _point(event.get("point"), width, height, "capture start")
                expected = _position(node, event_time)
                if str(event.get("node_id") or "") != str(node["id"]):
                    return _fail(f"event {sequence} targets the wrong echo order")
                if _polarization_error(polarization, float(node["polarization_deg"])) > float(requirements["polarization_tolerance_deg"]):
                    return _fail(f"event {sequence} uses the wrong polarization")
                if math.hypot(point[0] - expected[0], point[1] - expected[1]) > float(requirements["lock_radius"]):
                    return _fail(f"event {sequence} misses the moving echo")
                hold = {"node": node, "started": event_time, "tracks": 0, "last": point}
            elif kind == "lock_track":
                if hold is None or str(event.get("node_id") or "") != str(hold["node"]["id"]):
                    return _fail(f"event {sequence} tracks no matching echo")
                point = _point(event.get("point"), width, height, "capture track")
                expected = _position(hold["node"], event_time)
                if math.hypot(point[0] - expected[0], point[1] - expected[1]) > float(requirements["lock_radius"]):
                    return _fail(f"event {sequence} loses the moving echo")
                if math.hypot(point[0] - hold["last"][0], point[1] - hold["last"][1]) > 95:
                    return _fail(f"event {sequence} teleports the capture pointer")
                hold["last"] = point
                hold["tracks"] += 1
            elif kind in {"lock_end", "lock_cancel"}:
                if hold is None or str(event.get("node_id") or "") != str(hold["node"]["id"]):
                    return _fail(f"event {sequence} releases no matching echo")
                point = _point(event.get("point"), width, height, "capture release")
                duration = event_time - float(hold["started"])
                expected = _position(hold["node"], event_time)
                accepted = (
                    kind == "lock_end"
                    and duration >= float(requirements["minimum_hold_ms"])
                    and hold["tracks"] >= int(requirements["minimum_track_samples"])
                    and math.hypot(point[0] - expected[0], point[1] - expected[1]) <= float(requirements["lock_radius"])
                )
                if bool(event.get("accepted")) != accepted:
                    return _fail(f"event {sequence} lies about echo capture")
                if accepted:
                    locked_ids.append(str(hold["node"]["id"]))
                    current += 1
                else:
                    misses += 1
                hold = None
            elif kind == "reset":
                if hold is not None:
                    return _fail(f"event {sequence} resets during a hold")
                locked_ids = []
                current = 0
                reset_count += 1
            elif kind == "seal":
                if hold is not None:
                    return _fail(f"event {sequence} seals during a hold")
                seal_count += 1
            else:
                return _fail(f"event {sequence} has unknown kind {kind!r}")
        except (TypeError, ValueError) as exc:
            return _fail(f"event {sequence}: {exc}")

    expected = {
        "polarization_deg": polarization,
        "tuning_changes": tuning_changes,
        "probe_samples": probes,
        "probe_cells": len(cells),
        "locked_ids": locked_ids,
        "misses": misses,
        "reset_count": reset_count,
        "seal_count": seal_count,
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            return _fail(f"submitted {key} does not match palimpsest replay")
    passed = (
        payload.get("completed") is True
        and hold is None
        and current == len(nodes)
        and locked_ids == [str(node["id"]) for node in nodes]
        and probes >= int(requirements["minimum_probe_samples"])
        and len(cells) >= int(requirements["minimum_probe_cells"])
        and tuning_changes >= int(requirements["minimum_tuning_changes"])
        and seal_count >= 1
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": f"palimpsest replay: probes {probes}/{requirements['minimum_probe_samples']}; cells {len(cells)}/{requirements['minimum_probe_cells']}; turns {tuning_changes}; echoes {len(locked_ids)}/5; dropped holds {misses}; resets {reset_count}",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"echoes": [{"id": node["id"], "polarization_deg": node["polarization_deg"], "base": node["base"]} for node in ground_truth.get("nodes") or []], "answers": []}
