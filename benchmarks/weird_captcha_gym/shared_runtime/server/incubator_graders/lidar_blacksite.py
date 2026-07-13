from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "lidar_blacksite"


def _fail(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise ValueError(f"{label} must be finite")
    return float(value)


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label} must be an integer")
    return value


def _cross(first: tuple[float, float], second: tuple[float, float]) -> float:
    return first[0] * second[1] - first[1] * second[0]


def _ray_segment(origin: tuple[float, float], direction: tuple[float, float], first: tuple[float, float], second: tuple[float, float]) -> float | None:
    segment = (second[0] - first[0], second[1] - first[1])
    denominator = _cross(direction, segment)
    if abs(denominator) <= 1e-10:
        return None
    offset = (first[0] - origin[0], first[1] - origin[1])
    distance = _cross(offset, segment) / denominator
    amount = _cross(offset, direction) / denominator
    return distance if distance >= 0 and -1e-9 <= amount <= 1 + 1e-9 else None


def _ray_aabb(origin: tuple[float, float], direction: tuple[float, float], box: dict[str, Any]) -> float | None:
    minimum, maximum = box.get("min"), box.get("max")
    if not isinstance(minimum, list) or not isinstance(maximum, list) or len(minimum) != 2 or len(maximum) != 2:
        raise ValueError("AABB bounds are malformed")
    near, far = -math.inf, math.inf
    for axis in range(2):
        lower, upper = _number(minimum[axis], "AABB lower"), _number(maximum[axis], "AABB upper")
        if lower >= upper:
            raise ValueError("AABB is inverted")
        if abs(direction[axis]) <= 1e-12:
            if origin[axis] < lower or origin[axis] > upper:
                return None
            continue
        first = (lower - origin[axis]) / direction[axis]
        second = (upper - origin[axis]) / direction[axis]
        near, far = max(near, min(first, second)), min(far, max(first, second))
        if near > far:
            return None
    if far < 0:
        return None
    return max(0.0, near)


def _nearest_hit(origin: tuple[float, float], angle: float, walls: list[dict[str, Any]], occluders: list[dict[str, Any]], objects: list[dict[str, Any]], maximum_range: float) -> dict[str, Any] | None:
    direction = (math.cos(angle), math.sin(angle))
    candidates: list[tuple[float, int, str, str]] = []
    for wall in walls:
        distance = _ray_segment(origin, direction, tuple(wall["a"]), tuple(wall["b"]))
        if distance is not None:
            candidates.append((distance, 0, str(wall["id"]), "wall"))
    for item in occluders:
        distance = _ray_aabb(origin, direction, item)
        if distance is not None:
            candidates.append((distance, 1, str(item["id"]), "occluder"))
    for item in objects:
        distance = _ray_aabb(origin, direction, item)
        if distance is not None:
            candidates.append((distance, 2, str(item["id"]), str(item["kind"])))
    if not candidates:
        return None
    distance, _priority, item_id, kind = min(candidates)
    if distance > maximum_range:
        return None
    return {"id": item_id, "kind": kind, "distance": distance, "x": origin[0] + direction[0] * distance, "y": origin[1] + direction[1] * distance}


def _distance_point_segment(point: tuple[float, float], first: tuple[float, float], second: tuple[float, float]) -> float:
    dx, dy = second[0] - first[0], second[1] - first[1]
    denominator = dx * dx + dy * dy
    amount = 0.0 if denominator <= 1e-12 else max(0.0, min(1.0, ((point[0] - first[0]) * dx + (point[1] - first[1]) * dy) / denominator))
    nearest = (first[0] + dx * amount, first[1] + dy * amount)
    return math.hypot(point[0] - nearest[0], point[1] - nearest[1])


def _position_clear(point: tuple[float, float], radius: float, walls: list[dict[str, Any]], occluders: list[dict[str, Any]], world: dict[str, Any]) -> bool:
    width, height = _number(world.get("width"), "world width"), _number(world.get("height"), "world height")
    if point[0] - radius < 0 or point[0] + radius > width or point[1] - radius < 0 or point[1] + radius > height:
        return False
    if any(_distance_point_segment(point, tuple(wall["a"]), tuple(wall["b"])) < radius - 1e-8 for wall in walls):
        return False
    for item in occluders:
        nearest_x = max(float(item["min"][0]), min(point[0], float(item["max"][0])))
        nearest_y = max(float(item["min"][1]), min(point[1], float(item["max"][1])))
        if math.hypot(point[0] - nearest_x, point[1] - nearest_y) < radius - 1e-8:
            return False
    return True


def _line_of_sight(first: tuple[float, float], second: tuple[float, float], walls: list[dict[str, Any]], occluders: list[dict[str, Any]]) -> bool:
    distance = math.dist(first, second)
    if distance <= 1e-9:
        return True
    angle = math.atan2(second[1] - first[1], second[0] - first[0])
    direction = (math.cos(angle), math.sin(angle))
    for wall in walls:
        hit = _ray_segment(first, direction, tuple(wall["a"]), tuple(wall["b"]))
        if hit is not None and hit < distance - .04:
            return False
    for item in occluders:
        hit = _ray_aabb(first, direction, item)
        if hit is not None and hit < distance - .04:
            return False
    return True


def _validate_geometry(value: Any, kind: str, minimum: int, maximum: int) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not minimum <= len(value) <= maximum:
        raise ValueError(f"{kind} bank has invalid size")
    ids: set[str] = set()
    for item in value:
        if not isinstance(item, dict) or not str(item.get("id") or "") or str(item["id"]) in ids:
            raise ValueError(f"{kind} identity is malformed")
        ids.add(str(item["id"]))
        if kind == "wall":
            for key in ("a", "b"):
                point = item.get(key)
                if not isinstance(point, list) or len(point) != 2 or any(abs(_number(value, "wall coordinate")) > 40 for value in point):
                    raise ValueError("wall point is malformed")
        else:
            _ray_aabb((0.0, 0.0), (1.0, 0.0), item)
    return value


def _contract(ground_truth: dict[str, Any], public_state: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], dict[str, Any], dict[str, Any], dict[str, Any]]:
    for key in ("palette", "world", "walls", "occluders", "objects", "initial_player", "controls", "requirements"):
        if ground_truth.get(key) != public_state.get(key):
            raise ValueError(f"public {key} differs from hidden contract")
    world, initial, controls, requirements = (ground_truth.get(key) for key in ("world", "initial_player", "controls", "requirements"))
    if not all(isinstance(value, dict) for value in (world, initial, controls, requirements)):
        raise ValueError("world, player, controls, or requirements are malformed")
    walls = _validate_geometry(ground_truth.get("walls"), "wall", 12, 90)
    occluders = _validate_geometry(ground_truth.get("occluders"), "occluder", 1, 8)
    objects = _validate_geometry(ground_truth.get("objects"), "object", 2, 8)
    kinds = [str(item.get("kind") or "") for item in objects]
    if kinds.count("beacon") != 1 or kinds.count("exit") != 1:
        raise ValueError("beacon or extraction object is missing")
    return world, walls, occluders, objects, initial, controls, requirements


def _normalize_angle(angle: float) -> float:
    return (angle + math.pi) % (2 * math.pi) - math.pi


def _initial_player(initial: dict[str, Any]) -> dict[str, Any]:
    return {
        "x": _number(initial.get("x"), "initial x"),
        "y": _number(initial.get("y"), "initial y"),
        "heading": _integer(initial.get("heading_millirad"), "initial heading") / 1000,
        "tick": 0,
        "keys": {key: False for key in ("forward", "back", "strafe_left", "strafe_right", "turn_left", "turn_right")},
        "distance": 0.0,
        "collisions": 0,
    }


def _swept_move(player: dict[str, Any], dx: float, dy: float, radius: float, walls: list[dict[str, Any]], occluders: list[dict[str, Any]], world: dict[str, Any]) -> tuple[float, int]:
    distance = math.hypot(dx, dy)
    steps = max(1, math.ceil(distance / max(.01, radius * .25)))
    step_x, step_y = dx / steps, dy / steps
    moved, collisions = 0.0, 0
    for _ in range(steps):
        origin = (float(player["x"]), float(player["y"]))
        full = (origin[0] + step_x, origin[1] + step_y)
        if _position_clear(full, radius, walls, occluders, world):
            player["x"], player["y"] = full
            moved += math.hypot(step_x, step_y)
            continue
        collisions += 1
        x_only = (origin[0] + step_x, origin[1])
        y_only = (origin[0], origin[1] + step_y)
        moved_axis = False
        if abs(step_x) > 1e-12 and _position_clear(x_only, radius, walls, occluders, world):
            player["x"] = x_only[0]
            moved += abs(step_x)
            moved_axis = True
        if abs(step_y) > 1e-12 and _position_clear((float(player["x"]), y_only[1]), radius, walls, occluders, world):
            player["y"] = y_only[1]
            moved += abs(step_y)
            moved_axis = True
        if not moved_axis:
            player["x"], player["y"] = origin
    return moved, collisions


def _step(player: dict[str, Any], controls: dict[str, Any], world: dict[str, Any], walls: list[dict[str, Any]], occluders: list[dict[str, Any]]) -> None:
    dt = float(controls["tick_ms"]) / 1000
    turn = (1 if player["keys"]["turn_right"] else 0) - (1 if player["keys"]["turn_left"] else 0)
    player["heading"] = _normalize_angle(float(player["heading"]) + turn * math.radians(float(controls["turn_speed_deg"])) * dt)
    forward_amount = (1 if player["keys"]["forward"] else 0) - (1 if player["keys"]["back"] else 0)
    strafe_amount = (1 if player["keys"]["strafe_right"] else 0) - (1 if player["keys"]["strafe_left"] else 0)
    length = math.hypot(forward_amount, strafe_amount)
    if length:
        forward_amount, strafe_amount = forward_amount / length, strafe_amount / length
    cosine, sine = math.cos(float(player["heading"])), math.sin(float(player["heading"]))
    speed = float(controls["move_speed"])
    dx = (cosine * forward_amount - sine * strafe_amount) * speed * dt
    dy = (sine * forward_amount + cosine * strafe_amount) * speed * dt
    moved, collisions = _swept_move(player, dx, dy, float(controls["player_radius"]), walls, occluders, world)
    player["distance"] += moved
    player["collisions"] += collisions
    player["tick"] += 1


def _advance(player: dict[str, Any], target_tick: int, maximum_gap: int, controls: dict[str, Any], world: dict[str, Any], walls: list[dict[str, Any]], occluders: list[dict[str, Any]]) -> None:
    if target_tick < int(player["tick"]) or target_tick - int(player["tick"]) > maximum_gap:
        raise ValueError("movement tick reverses or skips beyond replay limits")
    while int(player["tick"]) < target_tick:
        _step(player, controls, world, walls, occluders)


def _clock(event: dict[str, Any], player: dict[str, Any], requirements: dict[str, Any], controls: dict[str, Any]) -> tuple[int, int]:
    tick = _integer(event.get("tick"), "event tick")
    elapsed = _integer(event.get("elapsed_ms"), "event clock")
    logical = tick * int(controls["tick_ms"])
    if elapsed < tick * 10 or elapsed > logical * 4 + 1600:
        raise ValueError("movement transcript is timestamp-compressed or detached from fixed ticks")
    if tick - int(player["tick"]) > int(requirements["maximum_event_gap_ticks"]):
        raise ValueError("movement event gap exceeds replay limit")
    return tick, elapsed


def _scan_hits(player: dict[str, Any], aim_millirad: int, controls: dict[str, Any], walls: list[dict[str, Any]], occluders: list[dict[str, Any]], objects: list[dict[str, Any]]) -> list[dict[str, Any]]:
    ray_count = int(controls["scan_rays"])
    half = math.radians(float(controls["scan_half_angle_deg"]))
    center = float(player["heading"]) + aim_millirad / 1000
    output = []
    for index in range(ray_count):
        amount = index / max(1, ray_count - 1)
        angle = center - half + amount * half * 2
        hit = _nearest_hit((float(player["x"]), float(player["y"])), angle, walls, occluders, objects, float(controls["scan_range"]))
        if hit:
            hit["ray_index"] = index
            output.append(hit)
    return output


def _validate_visible_returns(value: Any, expected: list[dict[str, Any]]) -> None:
    if not isinstance(value, list) or len(value) != len(expected):
        raise ValueError("visible LIDAR return count disagrees with nearest-hit replay")
    exact_keys = {"ray_index", "id", "kind", "distance", "x", "y"}
    for index, (visible, replayed) in enumerate(zip(value, expected)):
        if not isinstance(visible, dict) or set(visible) != exact_keys:
            raise ValueError(f"visible LIDAR return {index} has a malformed schema")
        if _integer(visible.get("ray_index"), "visible ray index") != int(replayed["ray_index"]):
            raise ValueError(f"visible LIDAR return {index} is attached to the wrong ray")
        if str(visible.get("id") or "") != str(replayed["id"]) or str(visible.get("kind") or "") != str(replayed["kind"]):
            raise ValueError(f"visible LIDAR return {index} reports the wrong nearest surface")
        for key in ("distance", "x", "y"):
            supplied = _number(visible.get(key), f"visible return {key}")
            if abs(supplied - round(supplied, 6)) > 5e-10:
                raise ValueError(f"visible LIDAR return {index} is not rounded to six decimals")
            if abs(supplied - round(float(replayed[key]), 6)) > 1.1e-6:
                raise ValueError(f"visible LIDAR return {index} {key} disagrees with world-anchored replay")


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
        world, walls, occluders, objects, initial, controls, requirements = _contract(ground_truth, public_state)
        player = _initial_player(initial)
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid blacksite geometry: {exc}")
    events = payload.get("events")
    if not isinstance(events, list) or not 1 <= len(events) <= 4000:
        return _fail("primitive blacksite transcript is missing or outside limits")
    beacon = next(item for item in objects if item["kind"] == "beacon")
    exit_object = next(item for item in objects if item["kind"] == "exit")
    beacon_center = ((float(beacon["min"][0]) + float(beacon["max"][0])) / 2, (float(beacon["min"][1]) + float(beacon["max"][1])) / 2)
    exit_center = ((float(exit_object["min"][0]) + float(exit_object["max"][0])) / 2, (float(exit_object["min"][1]) + float(exit_object["max"][1])) / 2)
    scan_count = key_transitions = 0
    stations: list[tuple[float, float]] = []
    first_scan_origin: tuple[float, float] | None = None
    target_scan_origin: tuple[float, float] | None = None
    target_seen = carrying = abandoned = submitted = terminal = False
    last_scan_tick = -10_000
    last_elapsed = -1

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return _fail(f"event {sequence} has invalid sequencing")
        if terminal:
            return _fail("transcript continues after terminal interaction")
        kind = str(event.get("kind") or "")
        try:
            tick, elapsed = _clock(event, player, requirements, controls)
            if elapsed < last_elapsed or elapsed > 600_000:
                raise ValueError("event clock reverses or exceeds session limits")
            _advance(player, tick, int(requirements["maximum_event_gap_ticks"]), controls, world, walls, occluders)
        except (KeyError, TypeError, ValueError) as exc:
            return _fail(f"event {sequence}: {exc}")
        if kind in {"key_down", "key_up"}:
            control = str(event.get("control") or "")
            if control not in player["keys"]:
                return _fail(f"event {sequence} invents movement control {control!r}")
            down = kind == "key_down"
            if bool(player["keys"][control]) == down:
                return _fail(f"event {sequence} duplicates a movement transition")
            player["keys"][control] = down
            key_transitions += 1
        elif kind == "scan":
            try:
                aim = _integer(event.get("aim_millirad"), "scan aim")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            if abs(aim) > 800 or tick - last_scan_tick < int(controls["scan_cooldown_ticks"]):
                return _fail(f"event {sequence} aims outside the scanner or bypasses cooldown")
            origin = (float(player["x"]), float(player["y"]))
            hits = _scan_hits(player, aim, controls, walls, occluders, objects)
            try:
                _validate_visible_returns(event.get("visible_returns"), hits)
            except (TypeError, ValueError) as exc:
                return _fail(f"event {sequence}: {exc}")
            scan_count += 1
            last_scan_tick = tick
            first_scan_origin = origin if first_scan_origin is None else first_scan_origin
            if not stations or all(math.dist(origin, station) >= float(requirements["station_distance"]) for station in stations):
                stations.append(origin)
            if any(hit["kind"] == "beacon" for hit in hits):
                target_seen = True
                target_scan_origin = origin
        elif kind == "pickup":
            if carrying:
                return _fail(f"event {sequence} picks up an already carried beacon")
            distance = math.dist((float(player["x"]), float(player["y"])), beacon_center)
            if not target_seen or distance > float(controls["pickup_range"]) or not _line_of_sight((float(player["x"]), float(player["y"])), beacon_center, walls, occluders):
                return _fail(f"event {sequence} violates beacon reveal, range, or line of sight")
            carrying = True
        elif kind == "submit":
            submitted = terminal = True
        elif kind == "abandon":
            abandoned = terminal = True
        elif kind == "stall":
            pass
        else:
            return _fail(f"event {sequence} has unknown primitive kind {kind!r}")
        last_elapsed = elapsed
    expected = {
        "scan_count": scan_count,
        "scan_station_count": len(stations),
        "key_transition_count": key_transitions,
        "collision_count": int(player["collisions"]),
        "carrying": carrying,
        "abandoned": abandoned,
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            return _fail(f"submitted {key} disagrees with independent replay")
    at_exit = math.dist((float(player["x"]), float(player["y"])), exit_center) <= float(controls["exit_radius"])
    target_displacement = math.dist(first_scan_origin, target_scan_origin) if first_scan_origin and target_scan_origin else 0.0
    replay_complete = bool(carrying and at_exit and target_seen)
    if payload.get("accepted") is not replay_complete:
        return _fail("client completion label disagrees with world replay")
    passed = bool(
        payload.get("completed") is True
        and submitted
        and not abandoned
        and replay_complete
        and scan_count >= int(requirements["minimum_scan_count"])
        and len(stations) >= int(requirements["minimum_scan_stations"])
        and target_displacement >= float(requirements["minimum_target_scan_displacement"])
        and float(player["distance"]) >= float(requirements["minimum_travel_distance"])
        and key_transitions >= int(requirements["minimum_key_transitions"])
        and int(player["tick"]) >= int(requirements["minimum_session_ticks"])
        and int(player["tick"]) <= int(requirements["maximum_session_ticks"])
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"blacksite replay: ticks {player['tick']}; travel {player['distance']:.2f}; scans {scan_count}; stations {len(stations)}; "
            f"target displacement {target_displacement:.2f}; collisions {player['collisions']}; beacon {'carried' if carrying else 'missing'}; exit {'reached' if at_exit else 'not reached'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    solution = ground_truth.get("solution") or {}
    return {
        "route_points": solution.get("route_points"),
        "scan_route_indices": solution.get("scan_route_indices"),
        "beacon_route_index": solution.get("beacon_route_index"),
        "instruction": "Follow the route with continuous movement, scan at separated stations, reveal and pick up the beacon, then continue to extraction.",
        "answers": [],
    }
