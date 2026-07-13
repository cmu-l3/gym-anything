from __future__ import annotations

import hashlib
import json
import math
from typing import Any


MECHANIC_ID = "tiny_fps_customs"


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _finite(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _integer(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _q(value: float) -> float:
    return round(value, 6)


def _normalize_angle(value: int) -> int:
    return value % 360_000


def _pose(value: Any) -> tuple[float, float, int] | None:
    if not isinstance(value, dict):
        return None
    x = _finite(value.get("x"))
    y = _finite(value.get("y"))
    angle = _integer(value.get("angle_mdeg"))
    if x is None or y is None or angle is None:
        return None
    return _q(x), _q(y), _normalize_angle(angle)


def _pose_matches(value: Any, expected: tuple[float, float, int]) -> bool:
    parsed = _pose(value)
    if parsed is None:
        return False
    return (
        abs(parsed[0] - expected[0]) <= 2e-5
        and abs(parsed[1] - expected[1]) <= 2e-5
        and parsed[2] == expected[2]
    )


def _manifest_digest(
    rows: list[str],
    initial_pose: dict[str, Any],
    creatures: list[dict[str, Any]],
    ammo: int,
) -> str:
    encoded = json.dumps(
        {"map": rows, "initial_pose": initial_pose, "creatures": creatures, "ammo": ammo},
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _circle_clear(rows: list[str], x: float, y: float, radius: float) -> bool:
    min_x = int(math.floor(x - radius))
    max_x = int(math.floor(x + radius))
    min_y = int(math.floor(y - radius))
    max_y = int(math.floor(y + radius))
    for cell_y in range(min_y, max_y + 1):
        for cell_x in range(min_x, max_x + 1):
            if cell_y < 0 or cell_y >= len(rows) or cell_x < 0 or cell_x >= len(rows[0]):
                return False
            if rows[cell_y][cell_x] != "#":
                continue
            nearest_x = max(cell_x, min(x, cell_x + 1))
            nearest_y = max(cell_y, min(y, cell_y + 1))
            dx = x - nearest_x
            dy = y - nearest_y
            if dx * dx + dy * dy < radius * radius - 1e-10:
                return False
    return True


def _ray_wall_distance(rows: list[str], x: float, y: float, angle_mdeg: int) -> float:
    angle = math.radians(angle_mdeg / 1000)
    direction_x, direction_y = math.cos(angle), math.sin(angle)
    map_x, map_y = int(math.floor(x)), int(math.floor(y))
    delta_x = abs(1 / direction_x) if abs(direction_x) > 1e-12 else 1e30
    delta_y = abs(1 / direction_y) if abs(direction_y) > 1e-12 else 1e30
    if direction_x < 0:
        step_x, side_x = -1, (x - map_x) * delta_x
    else:
        step_x, side_x = 1, (map_x + 1 - x) * delta_x
    if direction_y < 0:
        step_y, side_y = -1, (y - map_y) * delta_y
    else:
        step_y, side_y = 1, (map_y + 1 - y) * delta_y
    for _ in range(256):
        if side_x < side_y:
            distance = side_x
            side_x += delta_x
            map_x += step_x
        else:
            distance = side_y
            side_y += delta_y
            map_y += step_y
        if map_y < 0 or map_y >= len(rows) or map_x < 0 or map_x >= len(rows[0]):
            return distance
        if rows[map_y][map_x] == "#":
            return distance
    return 1e9


def _ray_creature_distance(
    x: float,
    y: float,
    angle_mdeg: int,
    creature: dict[str, Any],
    radius: float,
) -> float | None:
    creature_x = _finite(creature.get("x"))
    creature_y = _finite(creature.get("y"))
    if creature_x is None or creature_y is None:
        return None
    angle = math.radians(angle_mdeg / 1000)
    direction_x, direction_y = math.cos(angle), math.sin(angle)
    offset_x, offset_y = x - creature_x, y - creature_y
    b = direction_x * offset_x + direction_y * offset_y
    c = offset_x * offset_x + offset_y * offset_y - radius * radius
    discriminant = b * b - c
    if discriminant < 0:
        return None
    distance = -b - math.sqrt(discriminant)
    return distance if distance >= 0.04 else None


def _shot_result(
    rows: list[str],
    creatures: dict[str, dict[str, Any]],
    alive: set[str],
    x: float,
    y: float,
    angle_mdeg: int,
    radius: float,
) -> tuple[str, str | None, float]:
    wall_distance = _ray_wall_distance(rows, x, y, angle_mdeg)
    hit_id: str | None = None
    hit_distance = wall_distance
    for creature_id, creature in creatures.items():
        if creature_id not in alive:
            continue
        distance = _ray_creature_distance(x, y, angle_mdeg, creature, radius)
        if distance is not None and distance < hit_distance - 1e-8:
            hit_distance = distance
            hit_id = creature_id
    return ("creature", hit_id, hit_distance) if hit_id else ("wall", None, wall_distance)


def _identity_error(
    payload: dict[str, Any],
    ground_truth: dict[str, Any],
    public_state: dict[str, Any],
) -> str | None:
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID:
        return "payload mechanic mismatch"
    if str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return "hidden mechanic mismatch"
    if str(public_state.get("mechanic_id") or "") != MECHANIC_ID:
        return "public mechanic mismatch"
    hidden_challenge = str(ground_truth.get("challenge_id") or "")
    if not hidden_challenge or str(payload.get("challenge_id") or "") != hidden_challenge:
        return "stale challenge"
    if str(public_state.get("challenge_id") or "") != hidden_challenge:
        return "public and hidden challenge mismatch"
    hidden_task = str(ground_truth.get("task_id") or "")
    if str(payload.get("task_id") or "") != hidden_task:
        return "payload task mismatch"
    if str(public_state.get("task_id") or "") != hidden_task:
        return "public and hidden task mismatch"
    return None


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    identity_error = _identity_error(payload, ground_truth, public_state)
    if identity_error:
        return _failure(identity_error)

    rows = ground_truth.get("map")
    creatures_list = ground_truth.get("creatures")
    initial_raw = ground_truth.get("initial_pose")
    if (
        not isinstance(rows, list)
        or not rows
        or not all(isinstance(row, str) and len(row) == len(rows[0]) for row in rows)
        or not isinstance(creatures_list, list)
        or not isinstance(initial_raw, dict)
    ):
        return _failure("invalid hidden customs manifest")
    if rows != public_state.get("map") or creatures_list != public_state.get("creatures") or initial_raw != public_state.get("initial_pose"):
        return _failure("public world geometry differs from hidden manifest")

    ammo_total = _integer(ground_truth.get("ammo"))
    move_step = _finite(ground_truth.get("move_step"))
    player_radius = _finite(ground_truth.get("player_radius"))
    creature_radius = _finite(ground_truth.get("creature_radius"))
    initial = _pose(initial_raw)
    if (
        ammo_total is None
        or ammo_total <= 0
        or move_step is None
        or move_step <= 0
        or player_radius is None
        or player_radius <= 0
        or creature_radius is None
        or creature_radius <= 0
        or initial is None
    ):
        return _failure("invalid hidden movement manifest")
    if (
        ammo_total != _integer(public_state.get("ammo"))
        or abs(move_step - (_finite(public_state.get("move_step")) or -1)) > 1e-10
        or abs(player_radius - (_finite(public_state.get("player_radius")) or -1)) > 1e-10
        or abs(creature_radius - (_finite(public_state.get("creature_radius")) or -1)) > 1e-10
    ):
        return _failure("public physics constants differ from hidden manifest")

    creatures: dict[str, dict[str, Any]] = {}
    for creature in creatures_list:
        if not isinstance(creature, dict):
            return _failure("invalid hidden creature")
        creature_id = str(creature.get("id") or "")
        if not creature_id or creature_id in creatures:
            return _failure("duplicate hidden creature identity")
        creatures[creature_id] = creature
    wanted = {str(item) for item in ground_truth.get("wanted_ids") or []}
    protected = {str(item) for item in ground_truth.get("protected_ids") or []}
    if len(wanted) < 3 or len(protected) < 3 or wanted & protected or wanted | protected != set(creatures):
        return _failure("invalid hidden customs classifications")

    expected_digest = _manifest_digest(rows, initial_raw, creatures_list, ammo_total)
    if (
        str(ground_truth.get("manifest_digest") or "") != expected_digest
        or str(public_state.get("manifest_digest") or "") != expected_digest
    ):
        return _failure("customs manifest digest mismatch")

    actions = payload.get("actions")
    if not isinstance(actions, list) or not actions or len(actions) > 5000:
        return _failure("missing or oversized first-person transcript")

    x, y, angle_mdeg = initial
    alive = set(creatures)
    ammo = ammo_total
    previous_t = -1.0
    hit_ledger: list[dict[str, Any]] = []
    move_count = turn_count = shot_count = reset_count = collision_count = 0

    for index, action in enumerate(actions):
        if not isinstance(action, dict):
            return _failure(f"action {index + 1} is not an object")
        if _integer(action.get("seq")) != index + 1:
            return _failure("action sequence is not contiguous")
        action_t = _finite(action.get("t_ms"))
        if action_t is None or action_t < previous_t or action_t > 3_600_000:
            return _failure("action timestamps are invalid")
        previous_t = action_t
        action_type = str(action.get("type") or "")

        if action_type == "reset":
            x, y, angle_mdeg = initial
            alive = set(creatures)
            ammo = ammo_total
            hit_ledger = []
            reset_count += 1
            if not _pose_matches(action.get("pose"), (x, y, angle_mdeg)) or _integer(action.get("ammo")) != ammo:
                return _failure("reset does not restore the issued manifest")
            continue

        if action_type == "turn":
            delta = _integer(action.get("delta_mdeg"))
            if delta is None or delta == 0 or abs(delta) > 36_000:
                return _failure("turn delta is invalid")
            if _integer(action.get("before_mdeg")) != angle_mdeg:
                return _failure("reported turn origin differs from replay")
            angle_mdeg = _normalize_angle(angle_mdeg + delta)
            if _integer(action.get("after_mdeg")) != angle_mdeg:
                return _failure("reported turn result differs from replay")
            turn_count += 1
            continue

        if action_type == "move":
            forward = _integer(action.get("forward"))
            strafe = _integer(action.get("strafe"))
            if forward is None or strafe is None or forward not in {-1, 0, 1} or strafe not in {-1, 0, 1} or abs(forward) + abs(strafe) != 1:
                return _failure("movement vector is invalid")
            if not _pose_matches(action.get("from"), (x, y, angle_mdeg)):
                return _failure("reported movement origin differs from replay")
            angle = math.radians(angle_mdeg / 1000)
            intended_x = _q(x + (math.cos(angle) * forward + math.cos(angle + math.pi / 2) * strafe) * move_step)
            intended_y = _q(y + (math.sin(angle) * forward + math.sin(angle + math.pi / 2) * strafe) * move_step)
            blocked_x = not _circle_clear(rows, intended_x, y, player_radius)
            if not blocked_x:
                x = intended_x
            blocked_y = not _circle_clear(rows, x, intended_y, player_radius)
            if not blocked_y:
                y = intended_y
            x, y = _q(x), _q(y)
            if bool(action.get("blocked_x")) != blocked_x or bool(action.get("blocked_y")) != blocked_y:
                return _failure("reported wall collision differs from replay")
            if not _pose_matches(action.get("to"), (x, y, angle_mdeg)):
                return _failure("reported movement destination differs from replay")
            move_count += 1
            collision_count += int(blocked_x or blocked_y)
            continue

        if action_type == "shot":
            if not _pose_matches(action.get("origin"), (x, y, angle_mdeg)):
                return _failure("reported firing pose differs from replay")
            if _integer(action.get("ammo_before")) != ammo:
                return _failure("reported ammunition origin differs from replay")
            if ammo <= 0:
                expected_kind, hit_id, hit_distance = "empty", None, 0.0
            else:
                ammo -= 1
                expected_kind, hit_id, hit_distance = _shot_result(
                    rows, creatures, alive, x, y, angle_mdeg, creature_radius
                )
                if hit_id is not None:
                    alive.remove(hit_id)
                    hit_ledger.append({"shot": shot_count + 1, "creature_id": hit_id})
            if _integer(action.get("ammo_after")) != ammo:
                return _failure("reported ammunition result differs from replay")
            reported_kind = str(action.get("outcome") or "")
            reported_hit = action.get("hit_id")
            normalized_hit = str(reported_hit) if reported_hit is not None else None
            if reported_kind != expected_kind or normalized_hit != hit_id:
                return _failure("reported shot target differs from geometric replay")
            reported_distance = _finite(action.get("distance"))
            if reported_distance is None or abs(reported_distance - hit_distance) > 2e-4:
                return _failure("reported shot distance differs from geometric replay")
            shot_count += 1
            if hit_id in protected:
                return _failure("protected traveller was hit")
            continue

        return _failure(f"unknown transcript action {action_type!r}")

    eliminated_wanted = wanted - alive
    surviving_protected = protected & alive
    if eliminated_wanted != wanted or surviving_protected != protected:
        return _failure(
            f"customs unresolved: warrants {len(eliminated_wanted)}/{len(wanted)}, protected {len(surviving_protected)}/{len(protected)}"
        )
    if move_count < 1 or shot_count < len(wanted):
        return _failure("first-person interaction trace is incomplete")
    if payload.get("completed") is not True:
        return _failure("client did not certify customs completion")
    if not _pose_matches(payload.get("final_pose"), (x, y, angle_mdeg)):
        return _failure("final pose differs from replay")
    if _integer(payload.get("ammo_remaining")) != ammo:
        return _failure("final ammunition differs from replay")
    if [str(item) for item in payload.get("eliminated_ids") or []] != [
        item["creature_id"] for item in hit_ledger if item["creature_id"] in wanted
    ]:
        return _failure("elimination ledger differs from replay")
    if _integer(payload.get("protected_survivors")) != len(surviving_protected):
        return _failure("protected survivor count differs from replay")
    if payload.get("hit_ledger") != hit_ledger:
        return _failure("ordered hit ledger differs from replay")
    submitted_counts = payload.get("interaction_counts")
    replay_counts = {
        "moves": move_count,
        "turns": turn_count,
        "shots": shot_count,
        "collisions": collision_count,
        "resets": reset_count,
    }
    if submitted_counts != replay_counts:
        return _failure("interaction counters differ from replay")

    return {
        "graded": True,
        "passed": True,
        "score": 100,
        "feedback": (
            f"replayed {move_count} moves, {turn_count} turns and {shot_count} shots; "
            f"warrants 3/3, protected 3/3, ammo {ammo}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    if (
        str(public_state.get("mechanic_id") or "") != MECHANIC_ID
        or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID
        or str(public_state.get("challenge_id") or "") != str(ground_truth.get("challenge_id") or "")
    ):
        return {"error": "challenge identity mismatch"}
    return {
        "challenge_id": ground_truth.get("challenge_id"),
        "wanted_ids": list(ground_truth.get("wanted_ids") or []),
        "protected_ids": list(ground_truth.get("protected_ids") or []),
        "solver_plan": list(ground_truth.get("solver_plan") or []),
        "protected_test_plan": ground_truth.get("protected_test_plan"),
    }
