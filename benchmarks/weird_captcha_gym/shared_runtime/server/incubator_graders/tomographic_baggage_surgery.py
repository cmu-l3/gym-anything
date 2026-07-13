from __future__ import annotations

import json
import math
from typing import Any


MECHANIC_ID = "tomographic_baggage_surgery"
AXIS_INDEX = {"x": 0, "y": 1, "z": 2}


def _round(value: float) -> float:
    return round(float(value), 4)


def _world_center(center: list[float], quarter: int) -> list[float]:
    q = quarter % 4; x, y, z = map(float, center)
    return ([x, y, z], [z, y, -x], [-x, y, -z], [-z, y, x])[q]


def intersection_records(contract: dict[str, Any], axis: str, offset: float, quarter: int) -> list[dict[str, Any]]:
    index = AXIS_INDEX[axis]; records = []
    remaining = {"x": (2, 1), "y": (0, 2), "z": (0, 1)}[axis]
    for solid in contract["solids"]:
        center = _world_center(solid["center"], quarter); distance = abs(offset - center[index]); kind = solid["kind"]
        if kind == "sphere":
            radius = float(solid["radius"])
            if distance > radius + 1e-9: continue
            cross = math.sqrt(max(0, radius * radius - distance * distance)); size_a = size_b = cross
        elif kind == "box":
            half = list(map(float, solid["half"])); world_half = [half[2], half[1], half[0]] if quarter % 2 else half
            if distance > world_half[index] + 1e-9: continue
            size_a, size_b = world_half[remaining[0]], world_half[remaining[1]]
        else:
            radius, half_segment = float(solid["radius"]), float(solid["half_segment"])
            if axis == "y":
                vertical = abs(offset - center[1])
                if vertical <= half_segment: cross = radius
                elif vertical <= half_segment + radius: cross = math.sqrt(max(0, radius * radius - (vertical - half_segment) ** 2))
                else: continue
                size_a = size_b = cross
            else:
                if distance > radius + 1e-9: continue
                cross = math.sqrt(max(0, radius * radius - distance * distance)); size_a, size_b = cross, half_segment + cross
        records.append({"id": solid["id"], "kind": kind, "material": solid["material"], "u": _round(center[remaining[0]]), "v": _round(center[remaining[1]]), "a": _round(size_a), "b": _round(size_b)})
    return sorted(records, key=lambda item: item["id"])


def _digest(records: list[dict[str, Any]]) -> str:
    return "|".join(f"{r['id']}:{r['kind']}:{r['material']}:{r['u']:.4f}:{r['v']:.4f}:{r['a']:.4f}:{r['b']:.4f}" for r in records)


def _inside(solid: dict[str, Any], point: list[float], extra: float = 0) -> bool:
    center = solid["center"]; dx, dy, dz = (point[i] - center[i] for i in range(3))
    if solid["kind"] == "sphere": return dx * dx + dy * dy + dz * dz <= (solid["radius"] + extra) ** 2
    if solid["kind"] == "box": return all(abs(point[i] - center[i]) <= solid["half"][i] + extra for i in range(3))
    radial = math.hypot(dx, dz); vertical = max(0, abs(dy) - solid["half_segment"])
    return radial * radial + vertical * vertical <= (solid["radius"] + extra) ** 2


def _sweep(start: list[float], end: list[float], contract: dict[str, Any], target_id: str, captured: bool) -> str | None:
    target = next(s for s in contract["solids"] if s["id"] == target_id)
    distance = math.dist(start, end); steps = max(1, math.ceil(distance / contract["probe"]["sweep_step"])); radius = max(contract["probe"]["radius"], target["radius"] if captured else 0)
    bounds = contract["bounds"]
    for step in range(1, steps + 1):
        t = step / steps; point = [start[i] + (end[i] - start[i]) * t for i in range(3)]
        if not (bounds["x"][0] + radius <= point[0] <= bounds["x"][1] - radius and -4.6 <= point[1] <= 4.6 and bounds["z"][0] + radius <= point[2] <= bounds["z"][1] - radius): return "suitcase-wall"
        for solid in contract["solids"]:
            if solid["id"] != target_id and _inside(solid, point, radius): return str(solid["id"])
    return None


def _screen_to_coord(view: dict[str, Any], screen: list[float], current: list[float]) -> list[float]:
    point = list(current)
    for screen_index, axis in enumerate(view["axes"]): point[AXIS_INDEX[axis]] = (float(screen[screen_index]) - view["center"][screen_index]) / (view["scale"] * view["signs"][screen_index])
    return point


def _bound(public: dict[str, Any], truth: dict[str, Any]) -> str | None:
    for field in ("task_id", "bounds", "solids", "probe", "views", "slice", "requirements"):
        if public.get(field) != truth.get(field): return field
    return None


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge, task_id = str(ground_truth.get("challenge_id") or ""), str(ground_truth.get("task_id") or "")
    if payload.get("mechanic_id") != MECHANIC_ID or ground_truth.get("mechanic_id") != MECHANIC_ID: return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge or payload.get("challenge_id") != challenge or public_state.get("challenge_id") != challenge: return {"graded": True, "passed": False, "feedback": "stale challenge"}
    if not task_id or payload.get("task_id") != task_id: return {"graded": True, "passed": False, "feedback": "task identity mismatch"}
    skew = _bound(public_state, ground_truth)
    if skew: return {"graded": True, "passed": False, "feedback": f"public/private tomography {skew} contract skew"}
    events = payload.get("events"); requirements = ground_truth["requirements"]
    if not isinstance(events, list) or not (1 <= len(events) <= requirements["max_events"]): return {"graded": True, "passed": False, "feedback": "tomography transcript missing or outside limits"}
    target_id = ground_truth["target_id"]; target = next(s for s in ground_truth["solids"] if s["id"] == target_id)
    probe = list(ground_truth["probe"]["initial"]); drag = None; captured = extracted = terminal = case_locked = False
    scan_rotation = 0
    observations: list[tuple[int, str, float]] = []; target_signatures: set[tuple[int, str, float]] = set(); damages = resets = 0; views_used: set[str] = set()
    for sequence, event in enumerate(events, 1):
        if terminal: return {"graded": True, "passed": False, "feedback": "interaction continued after extraction"}
        if not isinstance(event, dict) or event.get("sequence") != sequence: return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = event.get("kind")
        if kind == "rotate_case":
            old, new = int(event.get("from", -1)), int(event.get("to", -1))
            if case_locked or old != scan_rotation or new != (old + 1) % 4: return {"graded": True, "passed": False, "feedback": "rigid suitcase quarter-turn transition mismatch"}
            scan_rotation = new
        elif kind == "slice_observation":
            axis, quarter, offset = str(event.get("axis") or ""), int(event.get("rotation", -1)), float(event.get("offset", math.inf))
            if axis not in ground_truth["slice"]["axes"] or quarter not in ground_truth["slice"]["rotations"] or not (ground_truth["slice"]["minimum"] <= offset <= ground_truth["slice"]["maximum"]): return {"graded": True, "passed": False, "feedback": "invalid slice plane or suitcase rotation"}
            expected = intersection_records(ground_truth, axis, offset, quarter)
            if event.get("records") != expected or event.get("digest") != _digest(expected): return {"graded": True, "passed": False, "feedback": "visible plane/solid intersection record drift"}
            if case_locked: return {"graded": True, "passed": False, "feedback": "slice changed after surgery orientation lock"}
            if quarter != scan_rotation: return {"graded": True, "passed": False, "feedback": "slice observation used an unperformed suitcase rotation"}
            signature = (quarter, axis, round(offset, 4)); observations.append(signature)
            if any(record["id"] == target_id for record in expected): target_signatures.add(signature)
        elif kind == "lock_case":
            if case_locked or drag is not None or int(event.get("from_rotation", -1)) != scan_rotation or int(event.get("rotation", -1)) != 0: return {"graded": True, "passed": False, "feedback": "invalid surgery orientation lock"}
            scan_rotation = 0; case_locked = True
        elif kind == "probe_drag_start":
            view_id, screen = str(event.get("view_id") or ""), event.get("screen")
            if not case_locked or drag is not None or view_id not in ground_truth["views"] or not isinstance(screen, list) or len(screen) != 2: return {"graded": True, "passed": False, "feedback": "invalid probe registration start"}
            mapped = _screen_to_coord(ground_truth["views"][view_id], screen, probe)
            axes = [AXIS_INDEX[a] for a in ground_truth["views"][view_id]["axes"]]
            if math.hypot(*(mapped[i] - probe[i] for i in axes)) > .34: return {"graded": True, "passed": False, "feedback": "probe ray missed registered body"}
            drag = view_id; views_used.add(view_id)
        elif kind == "probe_sample":
            if drag is None or event.get("view_id") != drag or not isinstance(event.get("screen"), list): return {"graded": True, "passed": False, "feedback": "orphan or cross-view probe sample"}
            candidate = _screen_to_coord(ground_truth["views"][drag], event["screen"], probe); claim = event.get("coordinate")
            if not isinstance(claim, list) or len(claim) != 3 or math.dist(candidate, [float(v) for v in claim]) > .08: return {"graded": True, "passed": False, "feedback": "probe coordinate was not reconstructed from active view"}
            blocker = _sweep(probe, candidate, ground_truth, target_id, captured); accepted = blocker is None
            if (event.get("accepted") is True) != accepted or (None if accepted else str(event.get("blocker") or "")) != blocker: return {"graded": True, "passed": False, "feedback": "probe collision claim disagrees with swept solid replay"}
            if accepted: probe = candidate
            else: damages += 1
        elif kind == "probe_drag_end":
            if drag is None or event.get("view_id") != drag: return {"graded": True, "passed": False, "feedback": "invalid probe drag release"}
            drag = None
        elif kind == "reset_probe":
            if drag is not None or captured: return {"graded": True, "passed": False, "feedback": "probe reset during drag or after capture"}
            probe = list(ground_truth["probe"]["initial"]); resets += 1
        elif kind == "capture":
            if drag is not None or captured or not _inside(target, probe, ground_truth["probe"]["radius"]): return {"graded": True, "passed": False, "feedback": "target capture lacks geometric probe overlap"}
            captured = True
        elif kind == "withdrawal":
            if drag is not None or not captured or probe[1] < ground_truth["probe"]["exit_y"]: return {"graded": True, "passed": False, "feedback": "withdrawal lacks captured target or exit containment"}
            extracted = terminal = True
        else: return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}
    rotations = sorted(set(item[0] for item in observations)); offsets = [item[2] for item in observations]
    target_observations = len(target_signatures)
    summary = {"extracted": extracted, "captured": captured, "probe": [_round(v) for v in probe], "observations": len(observations), "rotations": rotations, "target_observations": target_observations, "damages": damages, "resets": resets, "views_used": sorted(views_used)}
    for field, value in summary.items():
        if field == "probe":
            actual = payload.get(field)
            if not isinstance(actual, list) or len(actual) != 3 or math.dist([float(v) for v in actual], value) > .01: return {"graded": True, "passed": False, "feedback": "submitted probe disagrees with replay"}
        elif payload.get(field) != value: return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with tomography replay"}
    observation_ok = len(observations) >= requirements["min_observations"] and len(rotations) >= requirements["min_rotations"] and offsets and max(offsets) - min(offsets) >= requirements["min_offset_span"] and target_observations >= requirements["min_target_observations"]
    passed = extracted and case_locked and damages == 0 and observation_ok and len(views_used) >= 2
    return {"graded": True, "passed": passed, "score": 100 if passed else 0, "feedback": f"tomography replay: slices {len(observations)}; rotations {len(rotations)}; views {len(views_used)}; damages {damages}; target {'extracted' if extracted else 'inside'}"}


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"target_id": ground_truth.get("target_id"), "solver": ground_truth.get("solver") or {}}
