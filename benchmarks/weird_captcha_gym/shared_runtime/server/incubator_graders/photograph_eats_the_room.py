from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "photograph_eats_the_room"


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def _close(first: Any, second: Any, tolerance: float = 0.08) -> bool:
    a, b = _number(first), _number(second)
    return a is not None and b is not None and abs(a - b) <= tolerance


def _point(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, dict):
        return None
    x, y = _number(value.get("x")), _number(value.get("y"))
    return None if x is None or y is None else (x, y)


def _round(value: float) -> float:
    return round(float(value) + 1e-12, 2)


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _angle_error(first: float, second: float) -> float:
    return abs((first - second + 180.0) % 360.0 - 180.0)


def _camera_claim(value: Any, camera: dict[str, float]) -> bool:
    return isinstance(value, dict) and _close(value.get("x"), camera["x"]) and _close(value.get("y"), camera["y"]) and _close(value.get("yaw_deg"), camera["yaw_deg"])


def _plane_claim(value: Any, plane: dict[str, float]) -> bool:
    return isinstance(value, dict) and all(_close(value.get(key), plane[key]) for key in ("lateral", "depth", "rotation_deg", "scale"))


def _projection_claim(value: Any, expected: dict[str, Any]) -> bool:
    # Camera integration is quantized to hundredths independently in JS and
    # Python. At a nearby source, the accepted 8cm camera seam can move an
    # endpoint by roughly 0.015 normalized screen units.
    if not isinstance(value, dict) or not _close(value.get("distance"), expected["distance"], 0.09):
        return False
    endpoints = value.get("endpoints")
    return isinstance(endpoints, list) and len(endpoints) == len(expected["endpoints"]) and all(
        isinstance(claimed, dict)
        and _close(claimed.get("u"), target["u"], 0.02)
        and _close(claimed.get("depth"), target["depth"], 0.09)
        for claimed, target in zip(endpoints, expected["endpoints"])
    )


def _projection(camera: dict[str, float], source: dict[str, Any], fov_deg: float, capture_range: float) -> dict[str, Any] | None:
    yaw = math.radians(camera["yaw_deg"])
    cosine, sine = math.cos(yaw), math.sin(yaw)
    projected = []
    for endpoint in source["endpoints"]:
        dx, dy = float(endpoint["x"]) - camera["x"], float(endpoint["y"]) - camera["y"]
        forward, side = dx * cosine + dy * sine, -dx * sine + dy * cosine
        if forward <= 0.2:
            return None
        u = 0.5 + side / (2.0 * forward * math.tan(math.radians(fov_deg / 2.0)))
        projected.append({"u": round(u, 4), "depth": round(forward, 4)})
    midpoint = source["midpoint"]
    distance = math.hypot(float(midpoint["x"]) - camera["x"], float(midpoint["y"]) - camera["y"])
    if distance > capture_range or any(not 0.04 <= item["u"] <= 0.96 for item in projected):
        return None
    return {"endpoints": projected, "distance": round(distance, 4)}


def _occluded(camera: dict[str, float], source: dict[str, Any], room: dict[str, Any], operations: list[dict[str, Any]]) -> bool:
    wall_x = float(room["divider"]["x"])
    target_x, target_y = float(source["midpoint"]["x"]), float(source["midpoint"]["y"])
    if (camera["x"] - wall_x) * (target_x - wall_x) >= 0 or abs(target_x - camera["x"]) < 1e-9:
        return False
    amount = (wall_x - camera["x"]) / (target_x - camera["x"])
    crossing_y = camera["y"] + (target_y - camera["y"]) * amount
    opening = next((item for item in operations if item["operation"] == "carve_opening"), None)
    return opening is None or not _near_segment((wall_x, crossing_y), (opening["center"]["x"], opening["center"]["y"]), opening["angle_deg"], opening["length"], 0.45)


def _near_segment(point: tuple[float, float], center: tuple[float, float], angle_deg: float, length: float, half_width: float) -> bool:
    radians = math.radians(angle_deg)
    dx, dy = point[0] - center[0], point[1] - center[1]
    along = dx * math.cos(radians) + dy * math.sin(radians)
    across = -dx * math.sin(radians) + dy * math.cos(radians)
    return abs(along) <= length / 2.0 + 0.12 + 1e-9 and abs(across) <= half_width + 1e-9


def _collision_move(camera: dict[str, float], dx: float, dy: float, room: dict[str, Any], operations: list[dict[str, Any]], qualification: dict[str, Any]) -> dict[str, float]:
    radius = float(qualification["collision_radius"])
    bridge = next((item for item in operations if item["operation"] == "add_walkway"), None)
    opening = next((item for item in operations if item["operation"] == "carve_opening"), None)

    def valid(x: float, y: float, previous: tuple[float, float]) -> bool:
        if not radius <= x <= float(room["width"]) - radius or not radius <= y <= float(room["height"]) - radius:
            return False
        void = room["void"]
        if float(void["x1"]) <= x <= float(void["x2"]) and float(void["y1"]) <= y <= float(void["y2"]):
            if bridge is None or not _near_segment((x, y), (bridge["center"]["x"], bridge["center"]["y"]), bridge["angle_deg"], bridge["length"], float(qualification["bridge_half_width"])):
                return False
        wall_x = float(room["divider"]["x"])
        crosses_wall = (previous[0] - wall_x) * (x - wall_x) <= 0 and abs(x - previous[0]) > 1e-9
        inside_wall = abs(x - wall_x) < radius
        if crosses_wall or inside_wall:
            if opening is None or not _near_segment((wall_x, y), (opening["center"]["x"], opening["center"]["y"]), opening["angle_deg"], opening["length"], 0.45):
                return False
        return True

    old = (camera["x"], camera["y"])
    candidate = (old[0] + dx, old[1] + dy)
    if valid(*candidate, old):
        return {**camera, "x": _round(candidate[0]), "y": _round(candidate[1])}
    x_only = (old[0] + dx, old[1])
    if valid(*x_only, old):
        return {**camera, "x": _round(x_only[0])}
    y_only = (old[0], old[1] + dy)
    if valid(*y_only, old):
        return {**camera, "y": _round(y_only[1])}
    return dict(camera)


def _mapped(camera: dict[str, float], plane: dict[str, float], source: dict[str, Any]) -> dict[str, Any]:
    yaw = math.radians(camera["yaw_deg"])
    center = {
        "x": _round(camera["x"] + math.cos(yaw) * plane["depth"] - math.sin(yaw) * plane["lateral"]),
        "y": _round(camera["y"] + math.sin(yaw) * plane["depth"] + math.cos(yaw) * plane["lateral"]),
    }
    return {
        "center": center, "angle_deg": _round((camera["yaw_deg"] + plane["rotation_deg"]) % 360.0),
        "length": _round(float(source["length"]) * plane["scale"]),
    }


def _mapped_claim(value: Any, expected: dict[str, Any]) -> bool:
    center = _point(value.get("center")) if isinstance(value, dict) else None
    return center is not None and _close(center[0], expected["center"]["x"]) and _close(center[1], expected["center"]["y"]) and _close(value.get("angle_deg"), expected["angle_deg"]) and _close(value.get("length"), expected["length"])


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id, task_id = str(ground_truth.get("challenge_id") or ""), str(ground_truth.get("task_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("mechanic mismatch")
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return _failure("task mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return _failure("stale challenge")
    if str(public_state.get("mechanic_id") or "") != MECHANIC_ID or str(public_state.get("challenge_id") or "") != challenge_id or str(public_state.get("task_id") or "") != task_id:
        return _failure("public room identity mismatch")
    room, sources, sockets = ground_truth.get("room"), ground_truth.get("sources"), ground_truth.get("sockets")
    initial, controls, qualification = ground_truth.get("initial_camera"), ground_truth.get("controls"), ground_truth.get("qualification")
    if not isinstance(room, dict) or not isinstance(sources, list) or len(sources) != 2 or not isinstance(sockets, list) or len(sockets) != 2 or not all(isinstance(value, dict) for value in (initial, controls, qualification)):
        return _failure("hidden room manifest is malformed")
    for key, value in (("room", room), ("sources", sources), ("sockets", sockets), ("initial_camera", initial), ("controls", controls), ("qualification", qualification)):
        if public_state.get(key) != value:
            return _failure(f"public {key} disagrees with hidden room")
    events = payload.get("events")
    if not isinstance(events, list) or not events or len(events) > 1600:
        return _failure("room transcript is missing or too long")

    camera = {"x": float(initial["x"]), "y": float(initial["y"]), "yaw_deg": float(initial["yaw_deg"])}
    operations: list[dict[str, Any]] = []
    used_sources: set[str] = set()
    carrying: dict[str, Any] | None = None
    plane = {"lateral": 0.0, "depth": 1.2, "rotation_deg": 0.0, "scale": 1.0}
    moving: dict[str, Any] | None = None
    plane_dragging = False
    last_pointer = (0.5, 0.82)
    active = False
    terminal = False
    move_samples = 0
    travel = 0.0
    captures = 0
    local_failures = 0
    plane_resets = 0
    room_resets = 0
    capture_adjustments = {"drag_moves": 0, "rotations": 0, "scales": 0}
    previous_time = -1.0

    for sequence, event in enumerate(events, start=1):
        if terminal:
            return _failure(f"room event {sequence} occurs after terminal verification")
        if not isinstance(event, dict) or event.get("seq") != sequence:
            return _failure(f"room event {sequence} has invalid sequence")
        event_time = _number(event.get("t_ms"))
        if event_time is None or not 0 <= event_time <= 1_200_000 or event_time < previous_time:
            return _failure(f"room event {sequence} has invalid timestamp")
        previous_time = event_time
        action = str(event.get("type") or "")
        if action == "challenge_start":
            if active or sequence != 1 or not _camera_claim(event.get("camera"), camera):
                return _failure("room challenge start is malformed")
            active = True
            continue
        if not active:
            return _failure("room interaction occurred before the fresh plate cleared")
        if action == "move_start":
            code = str(event.get("code") or "")
            if moving is not None or plane_dragging or code not in {"forward", "back", "left", "right"} or not _camera_claim(event.get("camera"), camera):
                return _failure(f"movement {sequence} starts from impossible state")
            moving = {"code": code, "last_time": event_time}
            continue
        if action == "move_tick":
            if moving is None or plane_dragging:
                return _failure(f"movement sample {sequence} occurs without a held navigation key")
            dt = event_time - float(moving["last_time"])
            if not 25 <= dt <= float(qualification["maximum_move_sample_gap_ms"]) or not _close(event.get("dt_ms"), dt, 1.1) or not _camera_claim(event.get("from"), camera):
                return _failure(f"movement sample {sequence} compresses, dilates, or reports stale geometry")
            yaw = math.radians(camera["yaw_deg"])
            forward = (math.cos(yaw), math.sin(yaw)); right = (-math.sin(yaw), math.cos(yaw))
            direction = {"forward": forward, "back": (-forward[0], -forward[1]), "right": right, "left": (-right[0], -right[1])}[moving["code"]]
            distance = float(controls["move_speed"]) * dt / 1000.0
            before = (camera["x"], camera["y"])
            expected = _collision_move(camera, direction[0] * distance, direction[1] * distance, room, operations, qualification)
            if not _camera_claim(event.get("to"), expected):
                return _failure(f"movement sample {sequence} walks through collision or lies about position")
            camera = expected
            travel += math.hypot(camera["x"] - before[0], camera["y"] - before[1])
            move_samples += 1
            moving["last_time"] = event_time
            continue
        if action == "move_stall":
            if moving is None or plane_dragging or not _camera_claim(event.get("camera"), camera):
                return _failure(f"movement stall {sequence} occurs without a held navigation key")
            gap = event_time - float(moving["last_time"])
            if gap <= float(qualification["maximum_move_sample_gap_ms"]) or gap > 30_000 or not _close(event.get("gap_ms"), gap, 1.1):
                return _failure(f"movement stall {sequence} fabricates elapsed time")
            moving["last_time"] = event_time
            continue
        if action == "move_end":
            if moving is None or event_time - float(moving["last_time"]) > float(qualification["maximum_move_sample_gap_ms"]) or event.get("code") != moving["code"] or not _camera_claim(event.get("camera"), camera):
                return _failure(f"movement end {sequence} is malformed")
            moving = None
            continue
        if action == "turn":
            delta = event.get("delta_deg")
            if moving is not None or plane_dragging or delta not in {-15, 15} or not _camera_claim(event.get("before"), camera):
                return _failure(f"camera turn {sequence} is malformed")
            camera["yaw_deg"] = (camera["yaw_deg"] + int(delta)) % 360
            if not _camera_claim(event.get("after"), camera):
                return _failure(f"camera turn {sequence} reports false yaw")
            continue
        if action == "capture":
            if moving is not None or plane_dragging or carrying is not None or not _camera_claim(event.get("camera"), camera):
                return _failure(f"capture {sequence} occurs from impossible camera state")
            candidates = []
            for source in sources:
                if str(source["id"]) in used_sources:
                    continue
                projection = _projection(camera, source, float(controls["fov_deg"]), float(qualification["capture_range"]))
                if projection is not None and not _occluded(camera, source, room, operations):
                    candidates.append((projection["distance"], source, projection))
            if not candidates:
                return _failure(f"capture {sequence} contains no visible, unoccluded geometry")
            _distance, source, projection = min(candidates, key=lambda item: item[0])
            if event.get("captured_source_id") != source["id"] or not _projection_claim(event.get("projection"), projection):
                return _failure(f"capture {sequence} fabricates its camera frustum")
            carrying = source
            plane = {"lateral": 0.0, "depth": 1.2, "rotation_deg": 0.0, "scale": 1.0}
            capture_adjustments = {"drag_moves": 0, "rotations": 0, "scales": 0}
            captures += 1
            continue
        if action == "plane_drag_start":
            pointer = _point(event.get("pointer"))
            if carrying is None or moving is not None or plane_dragging or pointer is None or not 0 <= pointer[0] <= 1 or not 0 <= pointer[1] <= 1 or not _plane_claim(event.get("plane"), plane):
                return _failure(f"photo-plane drag {sequence} starts outside its physical pad")
            last_pointer = pointer; plane_dragging = True
            continue
        if action == "plane_drag_move":
            pointer = _point(event.get("pointer"))
            if not plane_dragging or carrying is None or pointer is None or not 0 <= pointer[0] <= 1 or not 0 <= pointer[1] <= 1 or math.hypot(pointer[0] - last_pointer[0], pointer[1] - last_pointer[1]) > float(qualification["maximum_plane_pointer_step"]):
                return _failure(f"photo-plane drag {sequence} teleports")
            if not _plane_claim(event.get("from"), plane):
                return _failure(f"photo-plane drag {sequence} has stale transform")
            plane["lateral"] = _round(float(controls["plane_lateral_min"]) + pointer[0] * (float(controls["plane_lateral_max"]) - float(controls["plane_lateral_min"])))
            plane["depth"] = _round(float(controls["plane_depth_min"]) + (1.0 - pointer[1]) * (float(controls["plane_depth_max"]) - float(controls["plane_depth_min"])))
            if not _plane_claim(event.get("to"), plane):
                return _failure(f"photo-plane drag {sequence} reports false transform")
            last_pointer = pointer; capture_adjustments["drag_moves"] += 1
            continue
        if action == "plane_drag_end":
            if not plane_dragging or not _plane_claim(event.get("plane"), plane):
                return _failure(f"photo-plane drag end {sequence} is malformed")
            plane_dragging = False
            continue
        if action == "plane_rotate":
            delta = event.get("delta_deg")
            if carrying is None or moving is not None or plane_dragging or delta not in {-15, 15} or not _close(event.get("before"), plane["rotation_deg"]):
                return _failure(f"photo-plane rotation {sequence} is malformed")
            plane["rotation_deg"] = (plane["rotation_deg"] + int(delta)) % 360
            if not _close(event.get("after"), plane["rotation_deg"]):
                return _failure(f"photo-plane rotation {sequence} lies about orientation")
            capture_adjustments["rotations"] += 1
            continue
        if action == "plane_scale":
            delta = _number(event.get("delta"))
            if carrying is None or moving is not None or plane_dragging or delta not in {-0.1, 0.1} or not _close(event.get("before"), plane["scale"]):
                return _failure(f"photo-plane scale {sequence} is malformed")
            next_scale = _round(plane["scale"] + delta)
            if not float(controls["plane_scale_min"]) <= next_scale <= float(controls["plane_scale_max"]):
                return _failure("photo-plane scale exceeds its physical stops")
            plane["scale"] = next_scale
            if not _close(event.get("after"), plane["scale"]):
                return _failure(f"photo-plane scale {sequence} lies about size")
            capture_adjustments["scales"] += 1
            continue
        if action == "plane_reset":
            if carrying is None or moving is not None or plane_dragging:
                return _failure("photo-plane reset occurred outside a carried print")
            plane = {"lateral": 0.0, "depth": 1.2, "rotation_deg": 0.0, "scale": 1.0}
            capture_adjustments = {"drag_moves": 0, "rotations": 0, "scales": 0}
            plane_resets += 1
            if not _plane_claim(event.get("plane"), plane):
                return _failure("photo-plane reset reports false stops")
            continue
        if action == "develop":
            if carrying is None or moving is not None or plane_dragging or not _camera_claim(event.get("camera"), camera) or not _plane_claim(event.get("plane"), plane):
                return _failure(f"development {sequence} occurs from impossible state")
            mapped = _mapped(camera, plane, carrying)
            if not _mapped_claim(event.get("mapped"), mapped):
                return _failure(f"development {sequence} fabricates transformed geometry")
            socket = next((item for item in sockets if item["source_kind"] == carrying["kind"]), None)
            qualified = bool(socket) and math.hypot(mapped["center"]["x"] - float(socket["center"]["x"]), mapped["center"]["y"] - float(socket["center"]["y"])) <= float(socket["tolerance"]) and _angle_error(mapped["angle_deg"], float(socket["angle_deg"])) <= 10 and mapped["length"] >= float(socket["minimum_length"]) and capture_adjustments["drag_moves"] >= int(qualification["minimum_plane_drag_moves"]) and capture_adjustments["scales"] >= int(qualification["minimum_scale_changes"])
            if bool(event.get("developed")) != qualified:
                return _failure(f"development {sequence} lies about room overwrite")
            if qualified:
                operation = {"source_id": str(carrying["id"]), "operation": str(socket["operation"]), **mapped}
                operations.append(operation); used_sources.add(str(carrying["id"])); carrying = None
            else:
                local_failures += 1
            continue
        if action == "room_reset":
            if moving is not None or plane_dragging:
                return _failure("room rewind occurred during an active gesture")
            camera = {"x": float(initial["x"]), "y": float(initial["y"]), "yaw_deg": float(initial["yaw_deg"])}
            operations = []; used_sources = set(); carrying = None; plane = {"lateral": 0.0, "depth": 1.2, "rotation_deg": 0.0, "scale": 1.0}
            move_samples = 0; travel = 0.0; captures = 0; local_failures = 0; plane_resets = 0; room_resets += 1
            if not _camera_claim(event.get("camera"), camera):
                return _failure("room rewind reports false origin")
            continue
        if action == "verify":
            if moving is not None or plane_dragging:
                return _failure("terminal verification occurred during an active gesture")
            terminal_point = room["terminal"]
            contact_now = math.hypot(camera["x"] - float(terminal_point["x"]), camera["y"] - float(terminal_point["y"])) <= float(terminal_point["radius"])
            if bool(event.get("claimed_terminal")) != contact_now:
                return _failure("terminal event lies about physical contact")
            terminal = True
            continue
        return _failure(f"room event {sequence} has invalid action {action!r}")

    terminal_point = room["terminal"]
    terminal_contact = math.hypot(camera["x"] - float(terminal_point["x"]), camera["y"] - float(terminal_point["y"])) <= float(terminal_point["radius"])
    expected_state = {
        "camera": {"x": _round(camera["x"]), "y": _round(camera["y"]), "yaw_deg": _round(camera["yaw_deg"])},
        "operations": operations, "carrying_source_id": None if carrying is None else str(carrying["id"]),
        "captures": captures, "move_samples": move_samples, "travel": _round(travel),
        "local_failures": local_failures, "plane_resets": plane_resets, "room_resets": room_resets,
        "terminal_contact": terminal_contact,
    }
    claimed_state = payload.get("final_state")
    state_matches = isinstance(claimed_state, dict) and _camera_claim(claimed_state.get("camera"), expected_state["camera"])
    state_matches = state_matches and claimed_state.get("carrying_source_id") == expected_state["carrying_source_id"]
    state_matches = state_matches and all(claimed_state.get(key) == expected_state[key] for key in ("captures", "move_samples", "local_failures", "plane_resets", "room_resets", "terminal_contact"))
    state_matches = state_matches and _close(claimed_state.get("travel"), expected_state["travel"], 0.12)
    claimed_operations = claimed_state.get("operations") if isinstance(claimed_state, dict) else None
    state_matches = state_matches and isinstance(claimed_operations, list) and len(claimed_operations) == len(operations)
    if state_matches:
        for claimed, expected in zip(claimed_operations, operations):
            if not isinstance(claimed, dict) or claimed.get("source_id") != expected["source_id"] or claimed.get("operation") != expected["operation"] or not _mapped_claim(claimed, expected):
                state_matches = False
                break
    if not state_matches:
        return _failure("claimed room state does not match primitive replay")
    passed = terminal and terminal_contact and [item["operation"] for item in operations] == ["add_walkway", "carve_opening"] and move_samples >= int(qualification["minimum_move_samples"]) and travel >= float(qualification["minimum_travel"])
    return {
        "graded": True, "passed": passed, "score": 100 if passed else 0,
        "feedback": f"replayed {move_samples} timed movement samples over {travel:.1f}m; captures {captures}; developed {[item['operation'] for item in operations]}; local failures {local_failures}; plane resets {plane_resets}; terminal contact {terminal_contact}",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"solution": ground_truth.get("solution") or {}, "answers": []}
