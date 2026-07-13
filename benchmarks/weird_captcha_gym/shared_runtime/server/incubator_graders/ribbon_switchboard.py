from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "ribbon_switchboard"


def _point(value: Any, width: int, height: int, label: str) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2 or any(isinstance(item, bool) for item in value):
        raise ValueError(f"{label} point is malformed")
    if not all(isinstance(item, (int, float)) and math.isfinite(item) for item in value):
        raise ValueError(f"{label} point is not finite")
    point = int(value[0]), int(value[1])
    if list(point) != value or not (0 <= point[0] <= width and 0 <= point[1] <= height):
        raise ValueError(f"{label} point leaves the switchboard")
    return point


def _distance(first: tuple[int, int] | list[int], second: tuple[int, int] | list[int]) -> float:
    return math.hypot(first[0] - second[0], first[1] - second[1])


def _nearest(point: tuple[int, int], path: list[list[int]]) -> tuple[float, float]:
    best_distance, best_parameter = float("inf"), 0.0
    for index, (first, second) in enumerate(zip(path, path[1:])):
        vx, vy = second[0] - first[0], second[1] - first[1]
        length_sq = vx * vx + vy * vy
        amount = 0.0 if length_sq <= 0 else max(0.0, min(1.0, ((point[0] - first[0]) * vx + (point[1] - first[1]) * vy) / length_sq))
        x, y = first[0] + vx * amount, first[1] + vy * amount
        distance = math.hypot(point[0] - x, point[1] - y)
        if distance < best_distance:
            best_distance, best_parameter = distance, index + amount
    return best_distance, best_parameter


def _explored_enough(
    hover_count: int,
    cells: set[str],
    target_coverage: set[int],
    crossing_coverage: set[str],
    requirements: dict[str, Any],
) -> bool:
    return (
        hover_count >= int(requirements["min_hover_samples"])
        and len(cells) >= int(requirements["min_hover_cells"])
        and len(target_coverage) >= int(requirements["min_target_coverage"])
        and len(crossing_coverage) >= int(requirements["min_crossing_coverage"])
    )


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
        stage = dict(ground_truth.get("stage") or {})
        width, height = int(stage["width"]), int(stage["height"])
        ribbons = [dict(item) for item in ground_truth.get("ribbons") or []]
        if not 4 <= len(ribbons) <= 6:
            raise ValueError("four to six ribbons are required")
        target_path = [[int(value) for value in point] for point in ground_truth.get("target_path") or []]
        target_terminal = [int(value) for value in ground_truth["target_terminal"]]
        target_crossings = sorted([dict(item) for item in ground_truth.get("target_crossings") or []], key=lambda item: float(item["target_parameter"]))
        if len(target_path) < 80 or len(target_crossings) < 5:
            raise ValueError("target route or crossing sequence is incomplete")
        hover_radius = int(ground_truth["hover_radius"])
        corridor_radius = int(ground_truth["corridor_radius"])
        requirements = dict(ground_truth.get("requirements") or {})
        clearance = dict(ground_truth.get("clearance_audit") or {})
        if int(clearance["maximum_close_run"]) > 9 or float(clearance["minimum_target_crossing_spacing"]) < 1.8:
            raise ValueError("layout clearance audit failed")
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid ribbon contract: {exc}"}

    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 900):
        return {"graded": True, "passed": False, "feedback": "switchboard transcript is missing or outside limits"}
    hover_count = 0
    hover_cells: set[str] = set()
    target_coverage: set[int] = set()
    crossing_coverage: set[str] = set()
    trace: dict[str, Any] | None = None
    collision_pending = False
    collisions = rearm_count = 0
    completed = False
    completed_samples = completed_crossings = 0
    final_point: tuple[int, int] | None = None

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if completed:
            return {"graded": True, "passed": False, "feedback": "interaction continued after terminal lock"}
        if kind == "hover_probe":
            if trace is not None:
                return {"graded": True, "passed": False, "feedback": "local illumination overlapped a committed trace"}
            try:
                point = _point(event.get("point"), width, height, "hover")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            hover_count += 1
            hover_cells.add(f"{point[0] // 55}:{point[1] // 55}")
            target_coverage.update(index for index, path_point in enumerate(target_path) if _distance(point, path_point) <= hover_radius)
            crossing_coverage.update(
                str(crossing["id"])
                for crossing in target_crossings
                if _distance(point, crossing["point"]) <= hover_radius * 0.58
            )
            continue
        if kind == "rearm":
            if trace is not None or not collision_pending:
                return {"graded": True, "passed": False, "feedback": "re-arm occurred without a cancelled ribbon trace"}
            collision_pending = False
            rearm_count += 1
            continue
        if kind == "trace_start":
            if trace is not None or collision_pending or not _explored_enough(hover_count, hover_cells, target_coverage, crossing_coverage, requirements):
                return {"graded": True, "passed": False, "feedback": "trace began before meaningful local depth exploration"}
            try:
                raw = _point(event.get("raw"), width, height, "trace start")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            if event.get("sample_index") != 0 or int(event.get("elapsed_ms")) != 0 or _distance(raw, target_path[0]) > 25:
                return {"graded": True, "passed": False, "feedback": "continuous hold did not begin on the marked source"}
            trace = {"index": 0, "last_raw": raw, "last_parameter": 0.0, "last_elapsed": 0, "samples": 0, "crossing_cursor": 0}
            continue
        if kind == "trace_sample":
            if trace is None or collision_pending:
                return {"graded": True, "passed": False, "feedback": "ribbon sample has no continuous hold"}
            sample_index = int(event.get("sample_index"))
            if sample_index != trace["index"] + 1:
                return {"graded": True, "passed": False, "feedback": "ribbon sample index is not continuous"}
            try:
                raw = _point(event.get("raw"), width, height, "trace")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            elapsed = int(event.get("elapsed_ms"))
            if elapsed < trace["last_elapsed"] or _distance(raw, trace["last_raw"]) > int(requirements["max_raw_step"]):
                return {"graded": True, "passed": False, "feedback": "raw trace jumped or time reversed"}
            wall_distance, parameter = _nearest(raw, target_path)
            if wall_distance > corridor_radius:
                return {"graded": True, "passed": False, "feedback": "trace crossed a ribbon edge without cancellation"}
            if parameter + float(requirements["backtrack_tolerance"]) < trace["last_parameter"]:
                return {"graded": True, "passed": False, "feedback": "trace backtracked along the woven route"}
            if parameter - trace["last_parameter"] > float(requirements["max_parameter_jump"]):
                return {"graded": True, "passed": False, "feedback": "trace skipped an unobserved ribbon interval"}
            trace.update({"index": sample_index, "last_raw": raw, "last_parameter": parameter, "last_elapsed": elapsed, "samples": trace["samples"] + 1})
            while trace["crossing_cursor"] < len(target_crossings) and parameter >= float(target_crossings[trace["crossing_cursor"]]["target_parameter"]):
                trace["crossing_cursor"] += 1
            continue
        if kind == "trace_cancel":
            if trace is None or collision_pending:
                return {"graded": True, "passed": False, "feedback": "ribbon cancellation has no active hold"}
            reason = str(event.get("reason") or "")
            sample_index = int(event.get("sample_index"))
            try:
                raw = _point(event.get("raw"), width, height, "cancel")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            if reason == "wall":
                if sample_index != trace["index"] + 1 or _nearest(raw, target_path)[0] <= corridor_radius:
                    return {"graded": True, "passed": False, "feedback": "claimed ribbon edge collision is inconsistent"}
            elif reason == "release":
                if sample_index != trace["index"]:
                    return {"graded": True, "passed": False, "feedback": "early ribbon release is inconsistent"}
            else:
                return {"graded": True, "passed": False, "feedback": "unknown ribbon cancellation reason"}
            trace = None
            collision_pending = True
            collisions += 1
            continue
        if kind == "trace_end":
            if trace is None or collision_pending:
                return {"graded": True, "passed": False, "feedback": "terminal release has no continuous hold"}
            try:
                raw = _point(event.get("raw"), width, height, "terminal")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            elapsed = int(event.get("elapsed_ms"))
            if event.get("sample_index") != trace["index"] or _distance(raw, trace["last_raw"]) > 5 or _distance(raw, target_terminal) > corridor_radius:
                return {"graded": True, "passed": False, "feedback": "hold was not released on the intended terminal"}
            if (
                trace["samples"] < int(requirements["min_trace_samples"])
                or trace["crossing_cursor"] != len(target_crossings)
                or trace["last_parameter"] < len(target_path) - 2
                or elapsed < int(requirements["min_trace_ms"])
                or elapsed < trace["last_elapsed"]
            ):
                return {"graded": True, "passed": False, "feedback": "trace lacks ordered crossings, samples, or hold time"}
            completed = True
            completed_samples = trace["samples"]
            completed_crossings = trace["crossing_cursor"]
            final_point = raw
            trace = None
            continue
        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    expected = {
        "hover_count": hover_count,
        "explored_cells": len(hover_cells),
        "target_coverage": len(target_coverage),
        "crossing_coverage": len(crossing_coverage),
        "trace_samples": completed_samples,
        "crossings_followed": completed_crossings,
        "collisions": collisions,
        "rearm_count": rearm_count,
        "final_point": list(final_point) if final_point else None,
    }
    for field, value in expected.items():
        if payload.get(field) != value:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} does not match ribbon replay"}
    passed = completed and trace is None and not collision_pending and _explored_enough(hover_count, hover_cells, target_coverage, crossing_coverage, requirements)
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"ribbon replay: hover {hover_count}; target coverage {len(target_coverage)}; local crossings {len(crossing_coverage)}; "
            f"trace samples {completed_samples}; ordered crossings {completed_crossings}/{len(target_crossings)}; recovery {collisions}/{rearm_count}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "target_id": ground_truth.get("target_id"),
        "target_path": ground_truth.get("target_path"),
        "target_terminal": ground_truth.get("target_terminal"),
        "target_crossings": ground_truth.get("target_crossings"),
    }
