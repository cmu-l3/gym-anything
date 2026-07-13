from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "flat_prisoner"


def _fail(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise ValueError(f"{label} must be a finite number")
    return float(value)


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label} must be an integer")
    return value


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def _dot(first: tuple[float, float, float], second: tuple[float, float, float]) -> float:
    return sum(a * b for a, b in zip(first, second))


def _cross(first: tuple[float, float, float], second: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        first[1] * second[2] - first[2] * second[1],
        first[2] * second[0] - first[0] * second[2],
        first[0] * second[1] - first[1] * second[0],
    )


def _normalize(vector: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(_dot(vector, vector))
    if length <= 1e-12:
        raise ValueError("camera basis is degenerate")
    return tuple(value / length for value in vector)  # type: ignore[return-value]


def _camera_basis(camera: dict[str, Any]) -> dict[str, tuple[float, float, float]]:
    yaw = math.radians(_number(camera.get("yaw_deg"), "camera yaw"))
    pitch = math.radians(_number(camera.get("pitch_deg"), "camera pitch"))
    distance = _number(camera.get("distance"), "camera distance")
    target_raw = camera.get("target")
    if not isinstance(target_raw, list) or len(target_raw) != 3:
        raise ValueError("camera target must contain three numbers")
    target = tuple(_number(value, "camera target") for value in target_raw)
    eye = (
        target[0] + distance * math.cos(pitch) * math.sin(yaw),
        target[1] + distance * math.sin(pitch),
        target[2] + distance * math.cos(pitch) * math.cos(yaw),
    )
    forward = _normalize(tuple(target[index] - eye[index] for index in range(3)))
    right = _normalize(_cross(forward, (0.0, 1.0, 0.0)))
    up = _normalize(_cross(right, forward))
    return {"eye": eye, "forward": forward, "right": right, "up": up}


def _view_matrix(camera: dict[str, Any]) -> list[list[float]]:
    basis = _camera_basis(camera)
    eye, forward, right, up = basis["eye"], basis["forward"], basis["right"], basis["up"]
    return [
        [right[0], right[1], right[2], -_dot(right, eye)],
        [up[0], up[1], up[2], -_dot(up, eye)],
        [-forward[0], -forward[1], -forward[2], _dot(forward, eye)],
        [0.0, 0.0, 0.0, 1.0],
    ]


def _projection_matrix(viewport: dict[str, Any]) -> list[list[float]]:
    width, height = _number(viewport.get("width"), "viewport width"), _number(viewport.get("height"), "viewport height")
    fov = _number(viewport.get("fov_deg"), "field of view")
    near, far = _number(viewport.get("near"), "near plane"), _number(viewport.get("far"), "far plane")
    if width <= 0 or height <= 0 or not 20 <= fov <= 100 or not 0 < near < far:
        raise ValueError("projection contract is outside supported bounds")
    focal = 1 / math.tan(math.radians(fov) / 2)
    return [
        [focal / (width / height), 0.0, 0.0, 0.0],
        [0.0, focal, 0.0, 0.0],
        [0.0, 0.0, (far + near) / (near - far), 2 * far * near / (near - far)],
        [0.0, 0.0, -1.0, 0.0],
    ]


def _matmul(first: list[list[float]], second: list[list[float]]) -> list[list[float]]:
    return [[sum(first[row][index] * second[index][column] for index in range(4)) for column in range(4)] for row in range(4)]


def _matvec(matrix: list[list[float]], vector: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    return tuple(sum(matrix[row][index] * vector[index] for index in range(4)) for row in range(4))  # type: ignore[return-value]


def _project(point: list[Any], camera: dict[str, Any], viewport: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(point, list) or len(point) != 3:
        raise ValueError("world point must contain three coordinates")
    world = tuple(_number(value, "world coordinate") for value in point)
    matrix = _matmul(_projection_matrix(viewport), _view_matrix(camera))
    clip = _matvec(matrix, (world[0], world[1], world[2], 1.0))
    if clip[3] <= 1e-8:
        return {"x": -9999.0, "y": -9999.0, "depth": 9999.0, "visible": False}
    ndc_x, ndc_y, ndc_z = clip[0] / clip[3], clip[1] / clip[3], clip[2] / clip[3]
    return {
        "x": (ndc_x * .5 + .5) * float(viewport["width"]),
        "y": (1 - (ndc_y * .5 + .5)) * float(viewport["height"]),
        "depth": ndc_z,
        "visible": -1.2 <= ndc_x <= 1.2 and -1.2 <= ndc_y <= 1.2 and -1 <= ndc_z <= 1,
    }


def _segments(platforms: list[dict[str, Any]], camera: dict[str, Any], viewport: dict[str, Any]) -> list[dict[str, Any]]:
    output = []
    for platform in platforms:
        walk_edge = platform.get("walk_edge")
        if not isinstance(walk_edge, list) or len(walk_edge) != 2:
            raise ValueError("platform walk edge is malformed")
        first, second = _project(walk_edge[0], camera, viewport), _project(walk_edge[1], camera, viewport)
        left, right = (first, second) if first["x"] <= second["x"] else (second, first)
        output.append({
            "id": str(platform.get("id") or ""),
            "role": str(platform.get("role") or ""),
            "left": float(left["x"]),
            "right": float(right["x"]),
            "left_y": float(left["y"]),
            "right_y": float(right["y"]),
            "visible": bool(first["visible"] and second["visible"] and float(right["x"]) - float(left["x"]) >= 42),
        })
    return output


def _segment_y(segment: dict[str, Any], x: float) -> float:
    amount = (x - float(segment["left"])) / max(1e-9, float(segment["right"]) - float(segment["left"]))
    return float(segment["left_y"]) + (float(segment["right_y"]) - float(segment["left_y"])) * amount


def _topology(platforms: list[dict[str, Any]], camera: dict[str, Any], viewport: dict[str, Any]) -> dict[str, Any]:
    segments = _segments(platforms, camera, viewport)
    directed: dict[str, set[str]] = {str(segment["id"]): set() for segment in segments}
    joins: list[dict[str, Any]] = []
    for index, first in enumerate(segments):
        if not first["visible"]:
            continue
        for second in segments[index + 1 :]:
            if not second["visible"]:
                continue
            overlap_left = max(float(first["left"]), float(second["left"]))
            overlap_right = min(float(first["right"]), float(second["right"]))
            if overlap_right - overlap_left < 10:
                continue
            midpoint = (overlap_left + overlap_right) / 2
            separation = abs(_segment_y(first, midpoint) - _segment_y(second, midpoint))
            if separation <= 10:
                first_id, second_id = str(first["id"]), str(second["id"])
                directed[first_id].add(second_id)
                directed[second_id].add(first_id)
                joins.append({"a": first_id, "b": second_id, "overlap": overlap_right - overlap_left, "separation": separation})
    for first in segments:
        if not first["visible"]:
            continue
        for second in segments:
            if first is second or not second["visible"]:
                continue
            gap = float(second["left"]) - float(first["right"])
            if not 4 <= gap <= 74:
                continue
            rise = _segment_y(first, float(first["right"])) - _segment_y(second, float(second["left"]))
            if -42 <= rise <= 78:
                directed[str(first["id"])].add(str(second["id"]))
    start = next((str(item["id"]) for item in platforms if item.get("role") == "start"), "")
    exit_id = next((str(item["id"]) for item in platforms if item.get("role") == "exit"), "")
    reached = {start} if start else set()
    frontier = [start] if start else []
    while frontier:
        current = frontier.pop()
        for neighbor in directed.get(current, set()):
            if neighbor not in reached:
                reached.add(neighbor)
                frontier.append(neighbor)
    core_visible = all(segment["visible"] for segment in segments if not str(segment["id"]).startswith("decoy-"))
    return {
        "segments": segments,
        "joins": joins,
        "reachable": sorted(reached),
        "valid": bool(core_visible and len(joins) >= 2 and exit_id in reached),
        "start_id": start,
        "exit_id": exit_id,
    }


def _validate_platforms(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not 8 <= len(value) <= 12:
        raise ValueError("platform bank must contain eight to twelve surfaces")
    ids: set[str] = set()
    roles: list[str] = []
    for platform in value:
        if not isinstance(platform, dict):
            raise ValueError("platform entry is malformed")
        platform_id, role = str(platform.get("id") or ""), str(platform.get("role") or "")
        if not platform_id or platform_id in ids or role not in {"start", "bridge", "exit", "decoy"}:
            raise ValueError("platform identity or role is invalid")
        ids.add(platform_id)
        roles.append(role)
        vertices, faces = platform.get("vertices"), platform.get("faces")
        if not isinstance(vertices, list) or len(vertices) != 8 or not isinstance(faces, list) or len(faces) != 6:
            raise ValueError("platform prism is malformed")
        for point in vertices:
            if not isinstance(point, list) or len(point) != 3 or any(abs(_number(item, "platform coordinate")) > 120 for item in point):
                raise ValueError("platform coordinate leaves world bounds")
        if any(not isinstance(face, list) or len(face) != 4 or any(not isinstance(index, int) or not 0 <= index < 8 for index in face) for face in faces):
            raise ValueError("platform face indices are malformed")
    if roles.count("start") != 1 or roles.count("exit") != 1 or roles.count("bridge") < 3:
        raise ValueError("platform roles do not define a traversal")
    return value


def _contract(ground_truth: dict[str, Any], public_state: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    for key in ("palette", "viewport", "initial_camera", "controls", "physics", "requirements", "platforms", "start_surface_id", "exit_surface_id"):
        if public_state.get(key) != ground_truth.get(key):
            raise ValueError(f"public {key} differs from hidden contract")
    platforms = _validate_platforms(ground_truth.get("platforms"))
    viewport, initial, controls, physics, requirements = (ground_truth.get(key) for key in ("viewport", "initial_camera", "controls", "physics", "requirements"))
    if not all(isinstance(value, dict) for value in (viewport, initial, controls, physics, requirements)):
        raise ValueError("matrix, controls, or physics contract is malformed")
    _view_matrix(initial)
    _projection_matrix(viewport)
    return platforms, viewport, initial, controls, physics, requirements


def _copy_camera(camera: dict[str, Any]) -> dict[str, Any]:
    return {
        "yaw_deg": float(camera["yaw_deg"]),
        "pitch_deg": float(camera["pitch_deg"]),
        "distance": float(camera["distance"]),
        "target": [float(value) for value in camera["target"]],
    }


def _make_physics(topology: dict[str, Any], physics: dict[str, Any]) -> dict[str, Any]:
    start = next(segment for segment in topology["segments"] if segment["id"] == topology["start_id"])
    exit_segment = next(segment for segment in topology["segments"] if segment["id"] == topology["exit_id"])
    spawn_x = float(start["left"]) + 26
    spawn_y = _segment_y(start, spawn_x)
    return {
        "x": spawn_x,
        "y": spawn_y,
        "vx": 0.0,
        "vy": 0.0,
        "grounded": bool(start["visible"]),
        "alive": True,
        "reached": False,
        "left": False,
        "right": False,
        "jump_held": False,
        "tick": 0,
        "jumps": 0,
        "transitions": 0,
        "exit_x": float(exit_segment["right"]) - 20,
        "exit_y": _segment_y(exit_segment, float(exit_segment["right"]) - 20),
        "physics": physics,
        "segments": topology["segments"],
    }


def _surface_candidates(state: dict[str, Any], x: float) -> list[tuple[float, dict[str, Any]]]:
    half_width = float(state["physics"]["player_width"]) / 2
    output = []
    for segment in state["segments"]:
        if segment["visible"] and float(segment["left"]) - half_width <= x <= float(segment["right"]) + half_width:
            output.append((_segment_y(segment, _clamp(x, float(segment["left"]), float(segment["right"]))), segment))
    return output


def _step_physics(state: dict[str, Any]) -> None:
    if not state["alive"] or state["reached"]:
        state["tick"] += 1
        return
    physics = state["physics"]
    dt = float(physics["tick_ms"]) / 1000
    direction = (1 if state["right"] else 0) - (1 if state["left"] else 0)
    state["vx"] = direction * float(physics["move_speed"])
    old_y = float(state["y"])
    state["x"] = float(state["x"]) + float(state["vx"]) * dt
    if state["grounded"]:
        supports = [(abs(y - old_y), y) for y, _segment in _surface_candidates(state, float(state["x"])) if abs(y - old_y) <= 5]
        if supports:
            state["y"] = min(supports)[1]
            state["vy"] = 0.0
        else:
            state["grounded"] = False
    if not state["grounded"]:
        state["vy"] = float(state["vy"]) + float(physics["gravity"]) * dt
        next_y = float(state["y"]) + float(state["vy"]) * dt
        if state["vy"] >= 0:
            crossings = [(surface_y, segment) for surface_y, segment in _surface_candidates(state, float(state["x"])) if float(state["y"]) <= surface_y + 1 and next_y >= surface_y]
            if crossings:
                surface_y, _segment = min(crossings, key=lambda item: item[0])
                state["y"] = surface_y
                state["vy"] = 0.0
                state["grounded"] = True
            else:
                state["y"] = next_y
        else:
            state["y"] = next_y
    state["tick"] += 1
    if float(state["y"]) > float(physics["death_y"]) or float(state["x"]) < -70 or float(state["x"]) > 970:
        state["alive"] = False
    if state["alive"] and state["grounded"] and abs(float(state["x"]) - float(state["exit_x"])) <= float(physics["exit_radius"]) and abs(float(state["y"]) - float(state["exit_y"])) <= 8:
        state["reached"] = True


def _advance(state: dict[str, Any], target_tick: int, maximum_gap: int) -> None:
    if target_tick < int(state["tick"]) or target_tick - int(state["tick"]) > maximum_gap:
        raise ValueError("physics tick reverses or skips beyond replay limits")
    while int(state["tick"]) < target_tick:
        _step_physics(state)


def _physics_clock(event: dict[str, Any], state: dict[str, Any], freeze_elapsed: int) -> tuple[int, int]:
    tick = _integer(event.get("tick"), "physics tick")
    elapsed = _integer(event.get("elapsed_ms"), "event clock")
    logical = tick * int(state["physics"]["tick_ms"])
    if elapsed - freeze_elapsed < tick * 12 or elapsed - freeze_elapsed > logical * 3 + 800:
        raise ValueError("physics transcript is timestamp-compressed or detached from its ticks")
    return tick, elapsed


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    task_id, challenge_id = str(ground_truth.get("task_id") or ""), str(ground_truth.get("challenge_id") or "")
    for label, source in (("payload", payload), ("ground truth", ground_truth), ("public state", public_state)):
        if str(source.get("mechanic_id") or "") != MECHANIC_ID:
            return _fail(f"{label} mechanic mismatch")
    if not task_id or str(payload.get("task_id") or "") != task_id or str(public_state.get("task_id") or "") != task_id:
        return _fail("task binding mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return _fail("stale or cross-seed challenge")
    try:
        platforms, viewport, initial, controls, physics, requirements = _contract(ground_truth, public_state)
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid projection contract: {exc}")
    events = payload.get("events")
    if not isinstance(events, list) or not 1 <= len(events) <= 3000:
        return _fail("primitive interaction transcript is missing or outside limits")

    camera = _copy_camera(initial)
    mode = "camera"
    current_topology: dict[str, Any] | None = None
    prisoner: dict[str, Any] | None = None
    freeze_elapsed = 0
    last_elapsed = -1
    last_camera_elapsed = -1
    first_camera_elapsed: int | None = None
    camera_since_reset = 0
    camera_total = freeze_count = thaw_count = death_count = key_total = 0
    valid_freeze = abandoned = submitted = terminal = False
    final_jumps = final_transitions = final_ticks = 0

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return _fail(f"event {sequence} has invalid sequencing")
        if terminal:
            return _fail("transcript continues after a terminal event")
        try:
            elapsed = _integer(event.get("elapsed_ms"), "event clock")
        except ValueError as exc:
            return _fail(f"event {sequence}: {exc}")
        if elapsed < last_elapsed or elapsed > 600_000:
            return _fail(f"event {sequence} reverses or exceeds the session clock")
        kind = str(event.get("kind") or "")
        if kind in {"orbit", "pan", "dolly"}:
            if mode != "camera":
                return _fail(f"event {sequence} moves the 3D camera while projection is frozen")
            if last_camera_elapsed >= 0 and elapsed - last_camera_elapsed < 18:
                return _fail(f"event {sequence} compresses camera movement timestamps")
            try:
                if kind == "orbit":
                    yaw_delta = _number(event.get("yaw_delta"), "yaw delta")
                    pitch_delta = _number(event.get("pitch_delta"), "pitch delta")
                    if max(abs(yaw_delta), abs(pitch_delta)) > float(controls["orbit_step_deg"]) + .001 or abs(yaw_delta) + abs(pitch_delta) <= 1e-8:
                        raise ValueError("orbit delta leaves primitive bounds")
                    camera["yaw_deg"] = _clamp(float(camera["yaw_deg"]) + yaw_delta, float(controls["yaw_min"]), float(controls["yaw_max"]))
                    camera["pitch_deg"] = _clamp(float(camera["pitch_deg"]) + pitch_delta, float(controls["pitch_min"]), float(controls["pitch_max"]))
                elif kind == "pan":
                    x_delta = _number(event.get("x_delta"), "pan x delta")
                    y_delta = _number(event.get("y_delta"), "pan y delta")
                    if max(abs(x_delta), abs(y_delta)) > float(controls["pan_step"]) + .001 or abs(x_delta) + abs(y_delta) <= 1e-8:
                        raise ValueError("pan delta leaves primitive bounds")
                    camera["target"][0] = _clamp(float(camera["target"][0]) + x_delta, -5.0, 5.0)
                    camera["target"][1] = _clamp(float(camera["target"][1]) + y_delta, -2.0, 4.0)
                else:
                    delta = _number(event.get("delta"), "dolly delta")
                    if not 1e-8 < abs(delta) <= float(controls["dolly_step"]) + .001:
                        raise ValueError("dolly delta leaves primitive bounds")
                    camera["distance"] = _clamp(float(camera["distance"]) + delta, float(controls["distance_min"]), float(controls["distance_max"]))
            except (KeyError, TypeError, ValueError) as exc:
                return _fail(f"event {sequence}: {exc}")
            camera = {**camera, "yaw_deg": round(float(camera["yaw_deg"]), 6), "pitch_deg": round(float(camera["pitch_deg"]), 6), "distance": round(float(camera["distance"]), 6), "target": [round(float(value), 6) for value in camera["target"]]}
            camera_total += 1
            camera_since_reset += 1
            first_camera_elapsed = elapsed if first_camera_elapsed is None else first_camera_elapsed
            last_camera_elapsed = elapsed
        elif kind == "camera_reset":
            if mode != "camera":
                return _fail(f"event {sequence} resets a frozen camera")
            camera = _copy_camera(initial)
            camera_since_reset = 0
            first_camera_elapsed = None
            last_camera_elapsed = elapsed
        elif kind == "freeze":
            if mode != "camera":
                return _fail(f"event {sequence} freezes an already flat world")
            if last_camera_elapsed >= 0 and elapsed - last_camera_elapsed < int(requirements["minimum_freeze_settle_ms"]):
                return _fail(f"event {sequence} freezes before the camera settles")
            try:
                current_topology = _topology(platforms, camera, viewport)
                prisoner = _make_physics(current_topology, physics)
            except (KeyError, TypeError, ValueError, StopIteration) as exc:
                return _fail(f"event {sequence} cannot derive projection topology: {exc}")
            mode = "flat"
            freeze_count += 1
            freeze_elapsed = elapsed
            valid_freeze = bool(
                current_topology["valid"]
                and len(current_topology["joins"]) >= int(requirements["minimum_screen_joins"])
                and camera_since_reset >= int(requirements["minimum_camera_events"])
                and first_camera_elapsed is not None
                and elapsed - first_camera_elapsed >= int(requirements["minimum_camera_elapsed_ms"])
            )
        elif kind in {"key_down", "key_up"}:
            if mode != "flat" or prisoner is None:
                return _fail(f"event {sequence} sends prisoner controls outside flat mode")
            try:
                tick, _ = _physics_clock(event, prisoner, freeze_elapsed)
                _advance(prisoner, tick, int(requirements["maximum_event_gap_ticks"]))
            except (KeyError, TypeError, ValueError) as exc:
                return _fail(f"event {sequence}: {exc}")
            key = str(event.get("key") or "")
            down = kind == "key_down"
            mapping = {"left": "left", "right": "right", "jump": "jump_held"}
            if key not in mapping or bool(prisoner[mapping[key]]) == down:
                return _fail(f"event {sequence} duplicates or invents a key transition")
            prisoner[mapping[key]] = down
            prisoner["transitions"] += 1
            key_total += 1
            if key == "jump" and down and prisoner["grounded"] and prisoner["alive"] and not prisoner["reached"]:
                prisoner["vy"] = float(physics["jump_velocity"])
                prisoner["grounded"] = False
                prisoner["jumps"] += 1
        elif kind == "thaw":
            if mode != "flat" or prisoner is None:
                return _fail(f"event {sequence} thaws outside flat mode")
            try:
                tick, _ = _physics_clock(event, prisoner, freeze_elapsed)
                _advance(prisoner, tick, int(requirements["maximum_event_gap_ticks"]))
            except (KeyError, TypeError, ValueError) as exc:
                return _fail(f"event {sequence}: {exc}")
            if prisoner["reached"]:
                return _fail(f"event {sequence} thaws after reaching the exit")
            if not prisoner["alive"]:
                death_count += 1
            mode, prisoner, current_topology = "camera", None, None
            thaw_count += 1
            valid_freeze = False
        elif kind == "submit":
            if mode != "flat" or prisoner is None:
                return _fail(f"event {sequence} submits outside flat mode")
            try:
                tick, _ = _physics_clock(event, prisoner, freeze_elapsed)
                _advance(prisoner, tick, int(requirements["maximum_event_gap_ticks"])
                )
            except (KeyError, TypeError, ValueError) as exc:
                return _fail(f"event {sequence}: {exc}")
            final_jumps, final_transitions, final_ticks = int(prisoner["jumps"]), int(prisoner["transitions"]), int(prisoner["tick"])
            submitted = terminal = True
        elif kind == "abandon":
            abandoned = terminal = True
        else:
            return _fail(f"event {sequence} has unknown primitive kind {kind!r}")
        last_elapsed = elapsed

    expected = {
        "camera_event_count": camera_total,
        "freeze_count": freeze_count,
        "thaw_count": thaw_count,
        "death_count": death_count,
        "key_transition_count": key_total,
        "abandoned": abandoned,
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            return _fail(f"submitted {key} disagrees with primitive replay")
    reached = bool(prisoner and prisoner["reached"])
    passed = bool(
        payload.get("completed") is True
        and payload.get("accepted") is True
        and submitted
        and not abandoned
        and reached
        and valid_freeze
        and final_ticks >= int(requirements["minimum_traversal_ticks"])
        and final_ticks <= int(requirements["maximum_traversal_ticks"])
        and final_transitions >= int(requirements["minimum_key_transitions"])
        and final_jumps >= int(requirements["minimum_jumps"])
    )
    if payload.get("accepted") is not reached:
        return _fail("client completion label disagrees with fixed-step escape replay")
    join_count = len(current_topology["joins"]) if current_topology else 0
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": f"matrix replay: camera events {camera_total}; freezes {freeze_count}; joins {join_count}; traversal ticks {final_ticks}; jumps {final_jumps}; exit {'reached' if reached else 'not reached'}",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    solution = ground_truth.get("solution") or {}
    return {
        "camera": solution.get("camera"),
        "required_join_pairs": solution.get("required_join_pairs"),
        "instruction": "Reach this camera using primitive orbit, pan, and dolly controls; freeze; then traverse with two physical jumps.",
        "answers": [],
    }
