from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "forced_perspective_moving_day"


def _camera_coords(point: list[float], camera: dict[str, Any]) -> tuple[float, float, float]:
    dx, dy, dz = point[0] - camera["x"], point[1] - camera["y"], point[2] - camera["z"]
    cosine, sine = math.cos(camera["yaw"]), math.sin(camera["yaw"])
    return cosine * dx - sine * dz, dy, sine * dx + cosine * dz


def _project(point: list[float], camera: dict[str, Any]) -> tuple[float, float, float]:
    x, y, depth = _camera_coords(point, camera)
    return camera["center"][0] + camera["focal"] * x / depth, camera["center"][1] - camera["focal"] * y / depth, depth


def _release_pose(screen: list[float], depth: float, apparent: float, obj: dict[str, Any], camera: dict[str, Any]) -> tuple[list[float], float]:
    camera_x = (float(screen[0]) - camera["center"][0]) / camera["focal"] * depth
    cosine, sine = math.cos(camera["yaw"]), math.sin(camera["yaw"])
    world_x = camera["x"] + cosine * camera_x + sine * depth
    world_z = camera["z"] - sine * camera_x + cosine * depth
    scale = apparent * depth / (camera["focal"] * obj["reference_size"])
    vertical_size = obj["base_size"][2] if obj["role"] == "bridge" else obj["base_size"][1]
    return [world_x, vertical_size * scale / 2, world_z], scale


def _overlap(center_a: list[float], size_a: list[float], center_b: list[float], size_b: list[float]) -> bool:
    return abs(center_a[0] - center_b[0]) < (size_a[0] + size_b[0]) / 2 - 1e-6 and abs(center_a[1] - center_b[1]) < (size_a[1] + size_b[1]) / 2 - 1e-6


def _footprint(obj: dict[str, Any]) -> tuple[list[float], list[float]]:
    depth_size = obj["base_size"][1] if obj.get("orientation") == "flat" else obj["base_size"][2]
    return [obj["center"][0], obj["center"][2]], [obj["base_size"][0] * obj["scale"], depth_size * obj["scale"]]


def _placement_blocker(candidate: dict[str, Any], objects: dict[str, dict[str, Any]], contract: dict[str, Any]) -> str | None:
    center, size = _footprint(candidate); world = contract["world"]
    if center[0] - size[0] / 2 < world["x_bounds"][0] or center[0] + size[0] / 2 > world["x_bounds"][1] or center[1] - size[1] / 2 < world["z_bounds"][0] or center[1] + size[1] / 2 > world["z_bounds"][1]:
        return "room-boundary"
    door = world["door"]
    if abs(center[1] - door["z"]) < size[1] / 2 + door["thickness"] / 2 and abs(center[0]) + size[0] / 2 > door["half_gap"]:
        return "door-wall"
    gap = world["gap"]
    if candidate["role"] != "bridge" and center[1] + size[1] / 2 > gap[0] and center[1] - size[1] / 2 < gap[1]:
        return "floor-void"
    for other_id, other in objects.items():
        if other_id == candidate["id"]:
            continue
        other_center, other_size = _footprint(other)
        if _overlap(center, size, other_center, other_size):
            return other_id
    return None


def _zone(center: list[float], target: list[float], tolerance: float) -> bool:
    return math.hypot(center[0] - target[0], center[1] - target[1]) <= tolerance


def _readiness(objects: dict[str, dict[str, Any]], contract: dict[str, Any], excluded: str | None = None) -> tuple[bool, bool]:
    sign, crate = objects["sign"], objects["crate"]
    sign_center, sign_size = _footprint(sign); gap, radius = contract["world"]["gap"], contract["world"]["avatar_radius"]
    bridge_ready = (excluded != "sign" and sign["scale"] >= contract["bridge_zone"]["min_scale"]
                    and sign_center[1] - sign_size[1] / 2 <= gap[0] - radius - 0.05
                    and sign_center[1] + sign_size[1] / 2 >= gap[1] + radius + 0.05
                    and abs(sign_center[0]) + radius <= sign_size[0] / 2)
    crate_center, crate_size = _footprint(crate); slot = contract["slot"]
    door_open = (excluded != "crate" and crate["scale"] <= slot["max_scale"]
                 and abs(crate_center[0] - slot["center"][0]) + crate_size[0] / 2 <= slot["size"][0] / 2 + 1e-6
                 and abs(crate_center[1] - slot["center"][1]) + crate_size[1] / 2 <= slot["size"][1] / 2 + 1e-6)
    return bridge_ready, door_open


def _movement_blocker(start: list[float], end: list[float], objects: dict[str, dict[str, Any]], bridge_ready: bool, door_open: bool, contract: dict[str, Any]) -> str | None:
    world, radius = contract["world"], float(contract["world"]["avatar_radius"])
    distance = math.hypot(end[0] - start[0], end[1] - start[1]); steps = max(1, math.ceil(distance / 0.08))
    sign = objects["sign"]; sign_center, sign_size = _footprint(sign)
    for index in range(1, steps + 1):
        t = index / steps; point = [start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t]
        if point[0] - radius < world["x_bounds"][0] or point[0] + radius > world["x_bounds"][1] or point[1] < world["z_bounds"][0] or point[1] > world["z_bounds"][1]:
            return "room-boundary"
        if world["gap"][0] <= point[1] <= world["gap"][1]:
            supported = bridge_ready and abs(point[0] - sign_center[0]) + radius <= sign_size[0] / 2 and abs(point[1] - sign_center[1]) + radius <= sign_size[1] / 2
            if not supported: return "floor-void"
        door = world["door"]
        if abs(point[1] - door["z"]) <= door["thickness"] / 2 + radius and (not door_open or abs(point[0]) + radius > door["half_gap"]):
            return "impossible-door"
        for object_id, obj in objects.items():
            if object_id == "sign" and bridge_ready: continue
            center, size = _footprint(obj)
            if abs(point[0] - center[0]) < size[0] / 2 + radius and abs(point[1] - center[1]) < size[1] / 2 + radius:
                return object_id
    return None


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge, task_id = str(ground_truth.get("challenge_id") or ""), str(ground_truth.get("task_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge or str(payload.get("challenge_id") or "") != challenge or str(public_state.get("challenge_id") or "") != challenge:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return {"graded": True, "passed": False, "feedback": "task identity mismatch"}
    for field in ("task_id", "stage", "camera", "world", "objects", "slot", "bridge_zone", "depth_controls", "requirements"):
        if public_state.get(field) != ground_truth.get(field):
            return {"graded": True, "passed": False, "feedback": f"public/private forced-perspective {field} contract skew"}
    try:
        initial_objects = {item["id"]: {**item, "center": list(item["center"])} for item in ground_truth["objects"]}
        initial_camera = dict(ground_truth["camera"])
        controls, requirements = ground_truth["depth_controls"], ground_truth["requirements"]
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid perspective contract: {exc}"}
    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 2200):
        return {"graded": True, "passed": False, "feedback": "perspective transcript missing or outside limits"}
    objects = {key: {**value, "center": list(value["center"])} for key, value in initial_objects.items()}
    camera = dict(initial_camera); held: dict[str, Any] | None = None; aim = list(camera["center"])
    keys: set[str] = set(); tick = 0; collisions = resets = rejected = 0
    bridge_ready = door_open = completed = terminal = False

    for sequence, event in enumerate(events, 1):
        if terminal:
            return {"graded": True, "passed": False, "feedback": "interaction continued after impossible delivery"}
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind == "aim":
            screen = event.get("screen")
            if not isinstance(screen, list) or len(screen) != 2 or not (0 <= float(screen[0]) <= 980 and 0 <= float(screen[1]) <= 480):
                return {"graded": True, "passed": False, "feedback": "invalid perspective aim sample"}
            aim = [float(screen[0]), float(screen[1])]
            continue
        if kind == "pick":
            object_id, screen = str(event.get("object_id") or ""), event.get("screen")
            if held is not None or object_id not in objects or not isinstance(screen, list) or len(screen) != 2:
                return {"graded": True, "passed": False, "feedback": "invalid rigid-object pickup"}
            obj = objects[object_id]; projected_x, projected_y, depth = _project(obj["center"], camera)
            apparent = camera["focal"] * obj["reference_size"] * obj["scale"] / depth
            radius = max(float(requirements["pick_radius_px"]), apparent * 0.62)
            if depth <= camera["near"] or math.hypot(float(screen[0]) - projected_x, float(screen[1]) - projected_y) > radius:
                return {"graded": True, "passed": False, "feedback": "pickup ray missed projected rigid object"}
            if abs(float(event.get("apparent_px") or 0) - apparent) > float(requirements["projection_tolerance"]) or abs(float(event.get("depth") or 0) - depth) > float(requirements["projection_tolerance"]):
                return {"graded": True, "passed": False, "feedback": "pickup apparent size/depth was fabricated"}
            held = {"id": object_id, "apparent": apparent, "depth": depth}; aim = [float(screen[0]), float(screen[1])]
            bridge_ready, door_open = _readiness(objects, ground_truth, excluded=object_id)
            continue
        if kind == "depth":
            if held is None:
                return {"graded": True, "passed": False, "feedback": "depth changed without a held object"}
            delta, new_depth = float(event.get("delta") or 0), float(event.get("depth") or 0)
            if abs(abs(delta) - float(controls["step"])) > 0.001 or abs(new_depth - (held["depth"] + delta)) > 0.001 or not (controls["minimum"] - 0.001 <= new_depth <= controls["maximum"] + 0.001):
                return {"graded": True, "passed": False, "feedback": "held-depth control skipped or left legal range"}
            held["depth"] = new_depth
            continue
        if kind == "release":
            if held is None or event.get("object_id") != held["id"] or event.get("surface") != "floor":
                return {"graded": True, "passed": False, "feedback": "release lacks held object or floor surface"}
            obj = objects[held["id"]]; position, scale = _release_pose(aim, held["depth"], held["apparent"], obj, camera)
            claimed_position = event.get("position")
            if not isinstance(claimed_position, list) or len(claimed_position) != 3 or math.dist([float(v) for v in claimed_position], position) > float(requirements["projection_tolerance"]) or abs(float(event.get("scale") or 0) - scale) > float(requirements["projection_tolerance"]):
                return {"graded": True, "passed": False, "feedback": "fake apparent-scale release transform"}
            expected_orientation = "flat" if obj["role"] == "bridge" else "box"
            if event.get("orientation") != expected_orientation:
                return {"graded": True, "passed": False, "feedback": "released rigid-body orientation was fabricated"}
            candidate = {**obj, "center": position, "scale": scale, "orientation": expected_orientation}
            projected_release = _project(position, camera)
            blocker = "off-floor-ray" if abs(projected_release[1] - aim[1]) > 40 else _placement_blocker(candidate, objects, ground_truth)
            accepted = blocker is None
            if (event.get("accepted") is True) != accepted or (None if accepted else str(event.get("blocker") or "")) != blocker:
                return {"graded": True, "passed": False, "feedback": "release collision disagrees with transformed rigid footprint"}
            if accepted:
                objects[held["id"]] = candidate
                bridge_ready, door_open = _readiness(objects, ground_truth)
                held = None
            else:
                rejected += 1
                bridge_ready, door_open = _readiness(objects, ground_truth, excluded=held["id"])
            continue
        if kind == "key_transition":
            key = str(event.get("key") or "")
            if held is not None or key not in {"forward", "back", "left", "right"} or event.get("tick") != tick:
                return {"graded": True, "passed": False, "feedback": "invalid navigation key transition"}
            if event.get("down") is True: keys.add(key)
            else: keys.discard(key)
            continue
        if kind == "movement_tick":
            if held is not None or event.get("tick") != tick + 1 or tick >= int(requirements["max_movement_events"]):
                return {"graded": True, "passed": False, "feedback": "movement tick omitted, reversed, or exceeded"}
            tick += 1
            forward = (1 if "forward" in keys else 0) - (1 if "back" in keys else 0)
            strafe = (1 if "right" in keys else 0) - (1 if "left" in keys else 0)
            length = math.hypot(forward, strafe)
            if length: forward, strafe = forward / length, strafe / length
            step = ground_truth["world"]["move_step"]; sine, cosine = math.sin(camera["yaw"]), math.cos(camera["yaw"])
            start = [camera["x"], camera["z"]]; dx = (forward * sine + strafe * cosine) * step; dz = (forward * cosine - strafe * sine) * step
            candidate = [start[0] + dx, start[1] + dz]; full_blocker = _movement_blocker(start, candidate, objects, bridge_ready, door_open, ground_truth)
            resolution, contact = "full", None
            if full_blocker is not None:
                contact = full_blocker; resolution = "blocked"
                # Solid faces always permit tangential wall sliding. At a void lip,
                # require an explicit strafe input: seeded camera yaw alone must
                # not turn a pure-forward fall attempt into sideways locomotion.
                may_slide = full_blocker != "floor-void" or abs(strafe) > 1e-9
                if may_slide and abs(dx) > 1e-9 and _movement_blocker(start, [start[0] + dx, start[1]], objects, bridge_ready, door_open, ground_truth) is None:
                    candidate, resolution = [start[0] + dx, start[1]], "slide_x"
                elif may_slide and abs(dz) > 1e-9 and _movement_blocker(start, [start[0], start[1] + dz], objects, bridge_ready, door_open, ground_truth) is None:
                    candidate, resolution = [start[0], start[1] + dz], "slide_z"
            accepted = resolution != "blocked"
            if (event.get("accepted") is True) != accepted or event.get("resolution") != resolution or (str(event.get("contact") or "") if contact else None) != contact:
                return {"graded": True, "passed": False, "feedback": "avatar collision/support claim disagrees with replay"}
            if accepted: camera["x"], camera["z"] = candidate
            if contact: collisions += 1
            state = event.get("camera")
            if not isinstance(state, list) or len(state) != 3 or math.dist([float(state[0]), float(state[1]), float(state[2])], [camera["x"], camera["z"], camera["yaw"]]) > 0.015:
                return {"graded": True, "passed": False, "feedback": "avatar/camera teleport in movement trace"}
            continue
        if kind == "complete":
            if completed or held is not None or camera["z"] < ground_truth["world"]["exit_z"] or not bridge_ready or not door_open:
                return {"graded": True, "passed": False, "feedback": "shipment completion lacks bridge, keyed crate, and doorway traversal"}
            completed = terminal = True
            continue
        if kind == "reset":
            if held is not None or terminal:
                return {"graded": True, "passed": False, "feedback": "reset while holding object or after completion"}
            objects = {key: {**value, "center": list(value["center"])} for key, value in initial_objects.items()}; camera = dict(initial_camera)
            aim = list(camera["center"]); keys.clear(); tick = 0; bridge_ready = door_open = completed = False; resets += 1
            continue
        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    summary = {"completed": completed, "bridge_ready": bridge_ready, "door_open": door_open, "collisions": collisions,
               "rejected_releases": rejected, "resets": resets, "movement_ticks": tick,
               "camera": [round(camera["x"], 3), round(camera["z"], 3), round(camera["yaw"], 6)],
               "object_states": {key: {"center": [round(v, 3) for v in value["center"]], "scale": round(value["scale"], 4), "orientation": value["orientation"]} for key, value in sorted(objects.items())}}
    for field, value in summary.items():
        if field == "camera":
            submitted = payload.get(field)
            if not isinstance(submitted, list) or len(submitted) != 3 or math.dist([float(v) for v in submitted], value) > 0.01:
                return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with perspective replay"}
        elif field == "object_states":
            submitted = payload.get(field)
            if not isinstance(submitted, dict) or set(submitted) != set(value):
                return {"graded": True, "passed": False, "feedback": "submitted object_states disagrees with perspective replay"}
            for object_id, expected in value.items():
                actual = submitted.get(object_id)
                if not isinstance(actual, dict) or actual.get("orientation") != expected["orientation"] or abs(float(actual.get("scale", math.inf)) - expected["scale"]) > 0.001 or not isinstance(actual.get("center"), list) or len(actual["center"]) != 3 or math.dist([float(v) for v in actual["center"]], expected["center"]) > 0.01:
                    return {"graded": True, "passed": False, "feedback": "submitted object_states disagrees with perspective replay"}
        elif payload.get(field) != value:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with perspective replay"}
    passed = completed and bridge_ready and door_open
    return {"graded": True, "passed": passed, "score": 100 if passed else 0,
            "feedback": f"perspective replay: bridge {'ready' if bridge_ready else 'missing'}; key {'slotted' if door_open else 'wrong'}; movement {tick}; collisions {collisions}; resets {resets}"}


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"solver_targets": ground_truth.get("solver_targets") or {}, "camera": ground_truth.get("camera") or {}}
