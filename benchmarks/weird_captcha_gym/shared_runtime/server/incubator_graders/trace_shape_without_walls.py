from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "trace_shape_without_walls"


def _point(value: Any, width: int, height: int, label: str) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2 or any(isinstance(item, bool) for item in value):
        raise ValueError(f"{label} point is malformed")
    if not all(isinstance(item, (int, float)) and math.isfinite(item) for item in value):
        raise ValueError(f"{label} point is not finite")
    x, y = int(value[0]), int(value[1])
    if [x, y] != value or not (0 <= x <= width and 0 <= y <= height):
        raise ValueError(f"{label} point leaves the oscilloscope")
    return x, y


def _browser_round(value: float) -> int:
    return math.floor(value + 0.5)


def _distance(first: tuple[int, int] | list[int], second: tuple[int, int] | list[int]) -> float:
    return math.hypot(first[0] - second[0], first[1] - second[1])


def _drift(sample_index: int, spec: dict[str, Any]) -> tuple[int, int]:
    phase_x, phase_y = float(spec["phase_x"]), float(spec["phase_y"])
    dx = float(spec["amplitude_x"]) * (
        math.sin(phase_x + sample_index * float(spec["rate_x"])) - math.sin(phase_x)
    )
    dy = float(spec["amplitude_y"]) * (
        math.cos(phase_y + sample_index * float(spec["rate_y"])) - math.cos(phase_y)
    )
    return _browser_round(dx), _browser_round(dy)


def _effective(raw: tuple[int, int], sample_index: int, drift: dict[str, Any]) -> tuple[int, int]:
    dx, dy = _drift(sample_index, drift)
    return raw[0] + dx, raw[1] + dy


def _nearest_on_path(point: tuple[int, int], path: list[list[int]]) -> tuple[float, float]:
    best_distance = float("inf")
    best_progress = 0.0
    for index, (first, second) in enumerate(zip(path, path[1:])):
        ax, ay = float(first[0]), float(first[1])
        vx, vy = float(second[0] - first[0]), float(second[1] - first[1])
        length_sq = vx * vx + vy * vy
        if length_sq <= 0:
            t = 0.0
        else:
            t = max(0.0, min(1.0, ((point[0] - ax) * vx + (point[1] - ay) * vy) / length_sq))
        nearest = (ax + t * vx, ay + t * vy)
        distance = math.hypot(point[0] - nearest[0], point[1] - nearest[1])
        if distance < best_distance:
            best_distance = distance
            best_progress = index + t
    return best_distance, best_progress


def _probe_coverage(
    point: tuple[int, int],
    main_path: list[list[int]],
    branches: list[dict[str, Any]],
    radius: int,
) -> tuple[set[int], set[str]]:
    main_hits = {index for index, path_point in enumerate(main_path) if _distance(point, path_point) <= radius}
    off_main = _nearest_on_path(point, main_path)[0] > radius * 0.58
    branch_hits = {
        str(branch["id"])
        for branch in branches
        if off_main and any(
            _distance(point, path_point) <= radius * 0.62
            for path_point in branch["points"][max(1, len(branch["points"]) * 2 // 5) :]
        )
    }
    return main_hits, branch_hits


def _explored_enough(
    probe_count: int,
    cells: set[str],
    main_coverage: set[int],
    branch_coverage: set[str],
    requirements: dict[str, Any],
) -> bool:
    return (
        probe_count >= int(requirements["min_probe_samples"])
        and len(cells) >= int(requirements["min_probe_cells"])
        and len(main_coverage) >= int(requirements["min_main_coverage"])
        and len(branch_coverage) >= int(requirements["min_branch_coverage"])
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
        main_path = [[int(value) for value in point] for point in ground_truth.get("main_path") or []]
        branches = [dict(branch) for branch in ground_truth.get("branches") or []]
        if len(main_path) < 80 or not 3 <= len(branches) <= 4:
            raise ValueError("corridor geometry is incomplete")
        start = [int(value) for value in ground_truth["start"]]
        exit_point = [int(value) for value in ground_truth["exit"]]
        checkpoint_indices = [int(value) for value in ground_truth.get("checkpoint_indices") or []]
        if len(checkpoint_indices) < 9 or checkpoint_indices[0] != 0 or checkpoint_indices[-1] != len(main_path) - 1:
            raise ValueError("ordered checkpoints are incomplete")
        corridor_radius = int(ground_truth["corridor_radius"])
        sonar_radius = int(ground_truth["sonar_radius"])
        drift = dict(ground_truth.get("drift") or {})
        requirements = dict(ground_truth.get("requirements") or {})
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid blind-corridor contract: {exc}"}

    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 1_200):
        return {"graded": True, "passed": False, "feedback": "oscilloscope transcript is missing or outside limits"}

    probe_count = 0
    probe_cells: set[str] = set()
    main_coverage: set[int] = set()
    branch_coverage: set[str] = set()
    trace: dict[str, Any] | None = None
    collision_pending = False
    collision_count = 0
    rearm_count = 0
    completed = False
    completed_samples = 0
    completed_distance = 0.0
    final_probe: tuple[int, int] | None = None

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if completed:
            return {"graded": True, "passed": False, "feedback": "interaction continued after the exit trace completed"}
        if kind == "sonar_probe":
            if trace is not None:
                return {"graded": True, "passed": False, "feedback": "sonar probing overlapped a committed trace"}
            try:
                point = _point(event.get("point"), width, height, "sonar")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            probe_count += 1
            probe_cells.add(f"{point[0] // 55}:{point[1] // 55}")
            main_hits, branch_hits = _probe_coverage(point, main_path, branches, sonar_radius)
            main_coverage.update(main_hits)
            branch_coverage.update(branch_hits)
            continue
        if kind == "rearm":
            if trace is not None or not collision_pending:
                return {"graded": True, "passed": False, "feedback": "trace re-arm occurred without a cancelled trace"}
            collision_pending = False
            rearm_count += 1
            continue
        if kind == "trace_start":
            if trace is not None or collision_pending or not _explored_enough(probe_count, probe_cells, main_coverage, branch_coverage, requirements):
                return {"graded": True, "passed": False, "feedback": "trace began before sufficient sonar mapping or re-arm"}
            try:
                raw = _point(event.get("raw"), width, height, "raw trace")
                effective = _point(event.get("effective"), width, height, "effective trace")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            if event.get("sample_index") != 0 or int(event.get("elapsed_ms")) != 0:
                return {"graded": True, "passed": False, "feedback": "trace hold did not begin at sample zero"}
            if effective != _effective(raw, 0, drift) or _distance(raw, start) > 26 or _distance(effective, start) > corridor_radius:
                return {"graded": True, "passed": False, "feedback": "continuous hold did not begin on START"}
            trace = {
                "sample_index": 0,
                "last_raw": raw,
                "last_effective": effective,
                "last_elapsed": 0,
                "last_progress": 0.0,
                "checkpoint_cursor": 1,
                "samples": 0,
                "distance": 0.0,
            }
            continue
        if kind == "trace_sample":
            if trace is None or collision_pending:
                return {"graded": True, "passed": False, "feedback": "trace sample has no continuous pointer hold"}
            sample_index = int(event.get("sample_index"))
            if sample_index != trace["sample_index"] + 1:
                return {"graded": True, "passed": False, "feedback": "trace sample index is not continuous"}
            try:
                raw = _point(event.get("raw"), width, height, "raw trace")
                effective = _point(event.get("effective"), width, height, "effective trace")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            if effective != _effective(raw, sample_index, drift):
                return {"graded": True, "passed": False, "feedback": "crosswind transform was tampered"}
            elapsed = int(event.get("elapsed_ms"))
            if elapsed < trace["last_elapsed"] or elapsed > 120_000:
                return {"graded": True, "passed": False, "feedback": "trace hold timing is not monotonic"}
            raw_step = _distance(raw, trace["last_raw"])
            if raw_step > int(requirements["max_raw_step"]):
                return {"graded": True, "passed": False, "feedback": "raw pointer jumped across unobserved corridor space"}
            wall_distance, progress = _nearest_on_path(effective, main_path)
            if wall_distance > corridor_radius:
                return {"graded": True, "passed": False, "feedback": "committed trace crossed a hidden wall without cancellation"}
            if progress + 7 < trace["last_progress"] or progress - trace["last_progress"] > 8:
                return {"graded": True, "passed": False, "feedback": "trace progress skipped or reversed across hidden checkpoints"}
            trace["distance"] += _distance(effective, trace["last_effective"])
            trace.update({
                "sample_index": sample_index,
                "last_raw": raw,
                "last_effective": effective,
                "last_elapsed": elapsed,
                "last_progress": progress,
                "samples": trace["samples"] + 1,
            })
            cursor = trace["checkpoint_cursor"]
            if cursor < len(checkpoint_indices):
                checkpoint = main_path[checkpoint_indices[cursor]]
                if _distance(effective, checkpoint) <= max(25, corridor_radius - 8):
                    trace["checkpoint_cursor"] += 1
            continue
        if kind == "trace_cancel":
            if trace is None or collision_pending:
                return {"graded": True, "passed": False, "feedback": "trace cancellation has no active hold"}
            reason = str(event.get("reason") or "")
            sample_index = int(event.get("sample_index"))
            try:
                raw = _point(event.get("raw"), width, height, "cancel raw")
                effective = _point(event.get("effective"), width, height, "cancel effective")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            if reason == "wall":
                if sample_index != trace["sample_index"] + 1 or effective != _effective(raw, sample_index, drift):
                    return {"graded": True, "passed": False, "feedback": "wall-collision transform is inconsistent"}
                wall_distance, _ = _nearest_on_path(effective, main_path)
                if wall_distance <= corridor_radius:
                    return {"graded": True, "passed": False, "feedback": "claimed wall collision remained inside the corridor"}
            elif reason == "release":
                if sample_index != trace["sample_index"] or effective != _effective(raw, sample_index, drift):
                    return {"graded": True, "passed": False, "feedback": "early-release cancellation is inconsistent"}
            else:
                return {"graded": True, "passed": False, "feedback": "unknown trace cancellation reason"}
            trace = None
            collision_pending = True
            collision_count += 1
            continue
        if kind == "trace_end":
            if trace is None or collision_pending:
                return {"graded": True, "passed": False, "feedback": "trace ended without a continuous hold"}
            sample_index = int(event.get("sample_index"))
            try:
                raw = _point(event.get("raw"), width, height, "exit raw")
                effective = _point(event.get("effective"), width, height, "exit effective")
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            elapsed = int(event.get("elapsed_ms"))
            if sample_index != trace["sample_index"] or effective != _effective(raw, sample_index, drift):
                return {"graded": True, "passed": False, "feedback": "exit crosswind transform is inconsistent"}
            if _distance(raw, trace["last_raw"]) > 5 or _distance(effective, exit_point) > max(24, corridor_radius - 8):
                return {"graded": True, "passed": False, "feedback": "continuous hold was not released on EXIT"}
            if trace["checkpoint_cursor"] != len(checkpoint_indices):
                return {"graded": True, "passed": False, "feedback": "hidden checkpoints were not crossed in order"}
            if (
                trace["samples"] < int(requirements["min_trace_samples"])
                or trace["distance"] < int(requirements["min_trace_distance"])
                or elapsed < int(requirements["min_trace_ms"])
                or elapsed < trace["last_elapsed"]
            ):
                return {"graded": True, "passed": False, "feedback": "continuous trace lacks sample, distance, or hold-time evidence"}
            completed = True
            completed_samples = trace["samples"]
            completed_distance = trace["distance"]
            final_probe = effective
            trace = None
            continue
        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    expected = {
        "probe_count": probe_count,
        "explored_cells": len(probe_cells),
        "explored_main": len(main_coverage),
        "explored_branches": len(branch_coverage),
        "trace_samples": completed_samples,
        "trace_distance": _browser_round(completed_distance),
        "collisions": collision_count,
        "rearm_count": rearm_count,
        "final_probe": list(final_probe) if final_probe else None,
    }
    for field, value in expected.items():
        if payload.get(field) != value:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} does not match oscilloscope replay"}
    passed = (
        completed
        and trace is None
        and not collision_pending
        and _explored_enough(probe_count, probe_cells, main_coverage, branch_coverage, requirements)
        and completed_samples >= int(requirements["min_trace_samples"])
        and completed_distance >= int(requirements["min_trace_distance"])
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"blind-corridor replay: probes {probe_count}; main coverage {len(main_coverage)}; branches {len(branch_coverage)}/{len(branches)}; "
            f"trace samples {completed_samples}; distance {round(completed_distance)}; collisions recovered {collision_count}/{rearm_count}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "corridor": ground_truth.get("main_path"),
        "decoy_branches": ground_truth.get("branches"),
        "checkpoint_indices": ground_truth.get("checkpoint_indices"),
        "drift": ground_truth.get("drift"),
    }
