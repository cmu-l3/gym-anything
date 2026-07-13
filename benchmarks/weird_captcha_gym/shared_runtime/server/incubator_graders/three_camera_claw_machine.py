from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "three_camera_claw_machine"


def _round(value: float) -> float:
    return round(float(value), 4)


def _project(camera: dict[str, Any], point: list[float]) -> list[float]:
    matrix = camera["matrix"]
    return [_round(camera["origin"][row] + sum(matrix[row][col] * point[col] for col in range(3))) for row in range(2)]


def _digest(camera: dict[str, Any], claw: list[float], objects: dict[str, dict[str, Any]], captured: str | None) -> str:
    items = [("claw", claw)] + [(key, claw if key == captured else value["center"]) for key, value in sorted(objects.items())]
    return "|".join(f"{key}:{screen[0]:.4f}:{screen[1]:.4f}" for key, point in items for screen in [_project(camera, point)])


def _point_aabb(point: list[float], obstacle: dict[str, Any], radius: float) -> bool:
    return all(abs(point[i] - obstacle["center"][i]) <= obstacle["half"][i] + radius for i in range(3))


def _blocker(start: list[float], end: list[float], contract: dict[str, Any], carried_radius: float) -> str | None:
    distance = math.dist(start, end); steps = max(1, math.ceil(distance / contract["world"]["collision_step"])); bounds = contract["world"]["bounds"]
    for step in range(1, steps + 1):
        t = step / steps; point = [start[i] + (end[i] - start[i]) * t for i in range(3)]
        for i, axis in enumerate(("x", "y", "z")):
            if point[i] - carried_radius < bounds[axis][0] or point[i] + carried_radius > bounds[axis][1]: return "cage-boundary"
        for obstacle in contract["obstacles"]:
            if _point_aabb(point, obstacle, carried_radius): return str(obstacle["id"])
    return None


def _contained(point: list[float], radius: float, box: dict[str, Any]) -> bool:
    return all(abs(point[i] - box["center"][i]) + radius <= box["half"][i] + 1e-6 for i in range(3))


def _frames(tick: int, history: dict[int, tuple[list[float], dict[str, dict[str, Any]], str | None]], cameras: dict[str, Any]) -> dict[str, Any]:
    result = {}
    for view_id, camera in cameras.items():
        visible_tick = max(0, tick - int(camera["delay"])); claw, objects, captured = history[visible_tick]
        result[view_id] = {"tick": visible_tick, "digest": _digest(camera, claw, objects, captured)}
    return result


def _clone_objects(items: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {item["id"]: {**item, "center": list(item["center"])} for item in items}


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge, task_id = str(ground_truth.get("challenge_id") or ""), str(ground_truth.get("task_id") or "")
    if payload.get("mechanic_id") != MECHANIC_ID or ground_truth.get("mechanic_id") != MECHANIC_ID: return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge or payload.get("challenge_id") != challenge or public_state.get("challenge_id") != challenge: return {"graded": True, "passed": False, "feedback": "stale challenge"}
    if not task_id or payload.get("task_id") != task_id: return {"graded": True, "passed": False, "feedback": "task identity mismatch"}
    for field in ("task_id", "world", "initial", "objects", "obstacles", "chute", "cameras", "requirements"):
        if public_state.get(field) != ground_truth.get(field): return {"graded": True, "passed": False, "feedback": f"public/private claw {field} contract skew"}
    events = payload.get("events"); requirements = ground_truth["requirements"]
    if not isinstance(events, list) or not (1 <= len(events) <= requirements["max_events"]): return {"graded": True, "passed": False, "feedback": "claw transcript missing or outside limits"}
    initial = ground_truth["initial"]; position, velocity = list(initial["position"]), list(initial["velocity"]); objects = _clone_objects(ground_truth["objects"])
    gripper = "open"; captured = None; delivered = terminal = False; tick = collisions = resets = 0; pending_control = False; feeds_seen: set[str] = set()
    history = {0: (list(position), _clone_objects(list(objects.values())), captured)}
    for sequence, event in enumerate(events, 1):
        if terminal: return {"graded": True, "passed": False, "feedback": "interaction continued after chute delivery"}
        if not isinstance(event, dict) or event.get("sequence") != sequence: return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = event.get("kind")
        if kind == "control":
            if pending_control: return {"graded": True, "passed": False, "feedback": "control omitted its fixed physics tick"}
            axis = event.get("axis"); direction = int(event.get("direction", 0)); world = ground_truth["world"]
            if axis == "brake": velocity = [v * .15 for v in velocity]
            elif axis == "coast": pass
            elif axis in {"x", "y", "z"} and direction in {-1, 1}:
                index = {"x": 0, "y": 1, "z": 2}[axis]; velocity[index] += direction * world["acceleration"]
                speed = math.sqrt(sum(v * v for v in velocity))
                if speed > world["max_speed"]: velocity = [v * world["max_speed"] / speed for v in velocity]
            else: return {"graded": True, "passed": False, "feedback": "invalid six-axis claw control"}
            pending_control = True
        elif kind == "physics_tick":
            if not pending_control or event.get("tick") != tick + 1 or tick >= requirements["max_ticks"]: return {"graded": True, "passed": False, "feedback": "missing, duplicate, or excessive fixed physics tick"}
            tick += 1; start = list(position); candidate = [position[i] + velocity[i] for i in range(3)]
            carried_radius = ground_truth["world"]["claw_radius"] if captured is None else max(ground_truth["world"]["claw_radius"], objects[captured]["radius"])
            contact = _blocker(start, candidate, ground_truth, carried_radius); resolution = "full"
            if contact:
                resolved = list(start); moved = False
                for index in range(3):
                    trial = list(resolved); trial[index] = candidate[index]
                    if _blocker(resolved, trial, ground_truth, carried_radius) is None: resolved = trial; moved |= abs(trial[index] - start[index]) > 1e-9
                    else: velocity[index] = 0
                candidate = resolved; resolution = "slide" if moved else "blocked"; collisions += 1
            position = candidate; velocity = [v * ground_truth["world"]["damping"] for v in velocity]
            if captured: objects[captured]["center"] = list(position)
            history[tick] = (list(position), _clone_objects(list(objects.values())), captured); expected_frames = _frames(tick, history, ground_truth["cameras"])
            if event.get("resolution") != resolution or (str(event.get("contact") or "") if contact else None) != contact: return {"graded": True, "passed": False, "feedback": "claw collision/wall-slide claim disagrees with replay"}
            if not isinstance(event.get("position"), list) or math.dist([float(v) for v in event["position"]], position) > .01 or not isinstance(event.get("velocity"), list) or math.dist([float(v) for v in event["velocity"]], velocity) > .01: return {"graded": True, "passed": False, "feedback": "claw position or inertial velocity teleport"}
            if event.get("visible_frames") != expected_frames: return {"graded": True, "passed": False, "feedback": "staggered CCTV frame tick/projection digest drift"}
            feeds_seen.update(expected_frames); pending_control = False
        elif kind == "gripper":
            if pending_control: return {"graded": True, "passed": False, "feedback": "gripper operated between control and physics tick"}
            action = event.get("action")
            if action == "close" and gripper == "open":
                candidates = sorted((math.dist(position, obj["center"]), object_id) for object_id, obj in objects.items() if object_id != captured)
                expected = None
                for distance, object_id in candidates:
                    obj = objects[object_id]
                    if distance <= ground_truth["world"]["capture_distance"] and _blocker(obj["center"], position, ground_truth, obj["radius"]) is None:
                        expected = object_id; break
                if event.get("captured_id") != expected: return {"graded": True, "passed": False, "feedback": "fake geometric claw grab"}
                gripper = "closed"; captured = expected
                if captured: objects[captured]["center"] = list(position)
                history[tick] = (list(position), _clone_objects(list(objects.values())), captured)
            elif action == "open" and gripper == "closed":
                released = captured; expected_delivered = bool(released == ground_truth["target_id"] and _contained(position, objects[released]["radius"], ground_truth["chute"])) if released else False
                if event.get("released_id") != released or (event.get("delivered") is True) != expected_delivered: return {"graded": True, "passed": False, "feedback": "release/chute containment claim disagrees with replay"}
                gripper = "open"; captured = None
                history[tick] = (list(position), _clone_objects(list(objects.values())), captured)
                if expected_delivered: delivered = terminal = True
            else: return {"graded": True, "passed": False, "feedback": "invalid gripper transition"}
        elif kind == "reset_claw":
            if pending_control or captured: return {"graded": True, "passed": False, "feedback": "claw reset during motion primitive or carrying"}
            position, velocity = list(initial["position"]), list(initial["velocity"]); objects = _clone_objects(ground_truth["objects"]); gripper = "open"; tick = 0; history = {0: (list(position), _clone_objects(list(objects.values())), None)}; resets += 1
        else: return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}
    if pending_control: return {"graded": True, "passed": False, "feedback": "terminal transcript ended before physics tick"}
    summary = {"delivered": delivered, "position": [_round(v) for v in position], "velocity": [_round(v) for v in velocity], "captured_id": captured, "gripper": gripper, "ticks": tick, "collisions": collisions, "resets": resets, "feeds_seen": sorted(feeds_seen)}
    for field, value in summary.items():
        if field in {"position", "velocity"}:
            actual = payload.get(field)
            if not isinstance(actual, list) or len(actual) != 3 or math.dist([float(v) for v in actual], value) > .01: return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with claw replay"}
        elif payload.get(field) != value: return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with claw replay"}
    passed = delivered and set(summary["feeds_seen"]) == set(requirements["required_feeds"])
    return {"graded": True, "passed": passed, "score": 100 if passed else 0, "feedback": f"claw replay: ticks {tick}; feeds {len(feeds_seen)}/3; collisions {collisions}; marked artifact {'delivered' if delivered else 'inside'}"}


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"target_id": ground_truth.get("target_id"), "solver": ground_truth.get("solver") or {}}
