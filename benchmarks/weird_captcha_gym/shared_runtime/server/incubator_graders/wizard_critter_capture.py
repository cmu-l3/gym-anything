from __future__ import annotations

import copy
import hashlib
from typing import Any


MECHANIC_ID = "wizard_critter_capture"


def _fail(feedback: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": feedback}


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label} must be an integer")
    return value


def _point(value: Any, width: int, height: int, label: str) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{label} point is malformed")
    x = _integer(value[0], f"{label} x")
    y = _integer(value[1], f"{label} y")
    if not 0 <= x <= width or not 0 <= y <= height:
        raise ValueError(f"{label} point leaves the arena")
    return x, y


def _trunc_div(value: int, divisor: int) -> int:
    return int(value / divisor)


def _clamp(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, value))


def _signature(appearance: dict[str, Any]) -> str:
    encoded = "|".join(str(appearance[key]) for key in sorted(appearance))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()[:12]


def _inside_occluder(x10: int, y10: int, occluders: list[dict[str, Any]]) -> bool:
    x, y = x10 / 10, y10 / 10
    return any(
        int(item["x"]) <= x <= int(item["x"]) + int(item["width"])
        and int(item["y"]) <= y <= int(item["y"]) + int(item["height"])
        for item in occluders
    )


def _lure_vector(critter: dict[str, Any], lure: tuple[int, int]) -> tuple[int, int]:
    dx = lure[0] - int(critter["x10"])
    dy = lure[1] - int(critter["y10"])
    return (
        10 if dx > 250 else -10 if dx < -250 else 0,
        7 if dy > 220 else -7 if dy < -220 else 0,
    )


def _step_critter(
    critter: dict[str, Any], lure: tuple[int, int], frozen: bool, arena: dict[str, Any], occluders: list[dict[str, Any]]
) -> dict[str, Any]:
    next_critter = dict(critter)
    ax, ay = _lure_vector(next_critter, lure)
    next_critter["vx10"] = _clamp(int(next_critter["vx10"]) + ax, -74, 74)
    next_critter["vy10"] = _clamp(int(next_critter["vy10"]) + ay, -54, 54)
    divisor = 3 if frozen else 1
    next_critter["x10"] = int(next_critter["x10"]) + _trunc_div(int(next_critter["vx10"]), divisor)
    next_critter["y10"] = int(next_critter["y10"]) + _trunc_div(int(next_critter["vy10"]), divisor)
    minimum_y, maximum_y = int(arena["y_min"]) * 10, int(arena["y_max"]) * 10
    if int(next_critter["y10"]) < minimum_y:
        next_critter["y10"] = minimum_y + (minimum_y - int(next_critter["y10"]))
        next_critter["vy10"] = abs(int(next_critter["vy10"]))
    elif int(next_critter["y10"]) > maximum_y:
        next_critter["y10"] = maximum_y - (int(next_critter["y10"]) - maximum_y)
        next_critter["vy10"] = -abs(int(next_critter["vy10"]))
    minimum_x, maximum_x = int(arena["x_min"]) * 10, int(arena["x_max"]) * 10
    if int(next_critter["x10"]) > maximum_x:
        next_critter["x10"] = minimum_x + (int(next_critter["x10"]) - maximum_x)
        next_critter["portal_count"] = int(next_critter.get("portal_count", 0)) + 1
    elif int(next_critter["x10"]) < minimum_x:
        next_critter["x10"] = maximum_x - (minimum_x - int(next_critter["x10"]))
        next_critter["portal_count"] = int(next_critter.get("portal_count", 0)) + 1
    next_critter["occluded"] = _inside_occluder(int(next_critter["x10"]), int(next_critter["y10"]), occluders)
    if next_critter["occluded"]:
        next_critter["occluded_ticks"] = int(next_critter.get("occluded_ticks", 0)) + 1
    return next_critter


def _snapshot(critters: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "id": str(item["id"]),
            "x10": int(item["x10"]),
            "y10": int(item["y10"]),
            "vx10": int(item["vx10"]),
            "vy10": int(item["vy10"]),
            "portal_count": int(item.get("portal_count", 0)),
            "occluded": bool(item.get("occluded", False)),
            "occluded_ticks": int(item.get("occluded_ticks", 0)),
        }
        for item in critters
    ]


def _projectile_point(projectile: dict[str, Any], flight_ticks: int) -> tuple[int, int]:
    origin_x, origin_y = projectile["origin10"]
    aim_x, aim_y = projectile["aim10"]
    age = int(projectile["age"])
    return (
        origin_x + _trunc_div((aim_x - origin_x) * age, flight_ticks),
        origin_y + _trunc_div((aim_y - origin_y) * age, flight_ticks),
    )


def _projectile_public(projectile: dict[str, Any] | None) -> dict[str, Any] | None:
    if projectile is None:
        return None
    return {
        "id": str(projectile["id"]),
        "age": int(projectile["age"]),
        "x10": int(projectile["x10"]),
        "y10": int(projectile["y10"]),
        "aim": [int(projectile["aim10"][0]) // 10, int(projectile["aim10"][1]) // 10],
    }


def _bind(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> str | None:
    for label, value in (("payload", payload), ("ground-truth", ground_truth), ("public-state", public_state)):
        if str(value.get("mechanic_id") or "") != MECHANIC_ID:
            return f"{label} mechanic mismatch"
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return "stale challenge"
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return "public-state challenge mismatch"
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return "payload task mismatch"
    if str(public_state.get("task_id") or "") != task_id:
        return "public-state task mismatch"
    return None


def _contract(ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    for key in ("palette", "arena", "portals", "occluders", "critters", "target_cue", "requirements"):
        if public_state.get(key) != ground_truth.get(key):
            raise ValueError(f"public {key} differs from hidden contract")
    arena = ground_truth.get("arena")
    critters = ground_truth.get("critters")
    occluders = ground_truth.get("occluders")
    requirements = ground_truth.get("requirements")
    if not isinstance(arena, dict) or not isinstance(critters, list) or len(critters) != 5:
        raise ValueError("arena or familiar roster is malformed")
    if not isinstance(occluders, list) or len(occluders) < 3 or not isinstance(requirements, dict):
        raise ValueError("cover or ritual requirements are malformed")
    ids = [str(item.get("id") or "") for item in critters if isinstance(item, dict)]
    if len(ids) != 5 or len(set(ids)) != 5 or any(not item for item in ids):
        raise ValueError("familiar identities are malformed")
    target_id = str(ground_truth.get("target_id") or "")
    if target_id not in ids:
        raise ValueError("target familiar is absent")
    cue = ground_truth.get("target_cue")
    if not isinstance(cue, dict) or not isinstance(cue.get("appearance"), dict):
        raise ValueError("target sigil is malformed")
    matches = [item for item in critters if _signature(item["appearance"]) == cue.get("signature")]
    if len(matches) != 1 or str(matches[0]["id"]) != target_id:
        raise ValueError("target sigil does not bind exactly one familiar")
    width = _integer(arena.get("width"), "arena width")
    height = _integer(arena.get("height"), "arena height")
    flight_ticks = _integer(arena.get("net_flight_ticks"), "net flight")
    origin = _point(arena.get("projectile_origin"), width, height, "projectile origin")
    if width < 600 or height < 300 or flight_ticks < 6:
        raise ValueError("interception arena is underspecified")
    return {
        "arena": arena,
        "width": width,
        "height": height,
        "flight_ticks": flight_ticks,
        "origin": origin,
        "occluders": [dict(item) for item in occluders],
        "initial_critters": copy.deepcopy(critters),
        "target_id": target_id,
        "signature": str(cue["signature"]),
        "requirements": {key: int(value) for key, value in requirements.items()},
    }


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    binding_error = _bind(payload, ground_truth, public_state)
    if binding_error:
        return _fail(binding_error)
    try:
        contract = _contract(ground_truth, public_state)
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid observatory contract: {exc}")
    events = payload.get("events")
    if not isinstance(events, list) or not (4 <= len(events) <= 900):
        return _fail("interception transcript is missing or outside limits")

    requirements = contract["requirements"]
    arena = contract["arena"]
    critters = copy.deepcopy(contract["initial_critters"])
    target_id = contract["target_id"]
    tick = 0
    preview_complete = False
    preview_count = 0
    lure: tuple[int, int] | None = None
    freeze_active = False
    freeze_energy = requirements["freeze_energy_ticks"]
    freeze_ticks = 0
    freeze_downs = 0
    freeze_releases = 0
    nets = requirements["net_count"]
    cooldown = 0
    projectile: dict[str, Any] | None = None
    launch_count = 0
    target_captured = False
    target_hit_id: str | None = None
    decoy_hits = 0
    misses = 0
    reset_count = 0
    target_resolution_count = 0
    ritual_fault = False

    def reset_world() -> None:
        nonlocal critters, tick, preview_complete, lure, freeze_active, freeze_energy, freeze_ticks
        nonlocal freeze_downs, freeze_releases, nets, cooldown, projectile, launch_count
        nonlocal target_captured, target_hit_id, decoy_hits, misses, target_resolution_count, ritual_fault
        critters = copy.deepcopy(contract["initial_critters"])
        tick = 0
        preview_complete = False
        lure = None
        freeze_active = False
        freeze_energy = requirements["freeze_energy_ticks"]
        freeze_ticks = 0
        freeze_downs = 0
        freeze_releases = 0
        nets = requirements["net_count"]
        cooldown = 0
        projectile = None
        launch_count = 0
        target_captured = False
        target_hit_id = None
        decoy_hits = 0
        misses = 0
        target_resolution_count = 0
        ritual_fault = False

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return _fail(f"event {sequence} has an invalid sequence")
        kind = str(event.get("kind") or "")
        if target_captured:
            return _fail("transcript continues after a target intersection")

        if kind == "reset":
            if event.get("tick_before") != tick:
                return _fail(f"event {sequence} reset clock mismatch")
            reset_world()
            reset_count += 1
            continue

        if kind == "preview_complete":
            if preview_complete or tick != 0 or lure is not None:
                return _fail(f"event {sequence} repeats or delays the sigil preview")
            try:
                elapsed = _integer(event.get("elapsed_ms"), "preview elapsed")
            except ValueError as exc:
                return _fail(f"event {sequence} is malformed: {exc}")
            if elapsed < requirements["preview_min_ms"] or event.get("signature") != contract["signature"]:
                return _fail(f"event {sequence} does not prove the target observation window")
            preview_complete = True
            preview_count += 1
            continue

        if kind == "lure":
            if not preview_complete or lure is not None or tick != 0:
                return _fail(f"event {sequence} places the lure outside the opening ritual")
            try:
                point = _point(event.get("point"), contract["width"], contract["height"], "lure")
            except ValueError as exc:
                return _fail(f"event {sequence} is malformed: {exc}")
            lure = (point[0] * 10, point[1] * 10)
            target = next(item for item in critters if item["id"] == target_id)
            if event.get("target_vector") != list(_lure_vector(target, lure)):
                return _fail(f"event {sequence} lure vector disagrees with replay")
            continue

        if kind == "freeze_down":
            if not preview_complete or lure is None or freeze_active or freeze_energy <= 0 or event.get("key") != "f" or event.get("tick") != tick:
                return _fail(f"event {sequence} begins an invalid freeze hold")
            freeze_active = True
            freeze_downs += 1
            continue

        if kind == "freeze_up":
            if not freeze_active or event.get("key") != "f" or event.get("tick") != tick:
                return _fail(f"event {sequence} releases an inactive freeze hold")
            freeze_active = False
            freeze_releases += 1
            continue

        if kind == "net_launch":
            if not preview_complete or lure is None or projectile is not None or cooldown != 0 or nets <= 0:
                return _fail(f"event {sequence} launches through cooldown or without a net")
            if event.get("tick") != tick:
                return _fail(f"event {sequence} launch clock mismatch")
            try:
                aim = _point(event.get("aim"), contract["width"], contract["height"], "net aim")
            except ValueError as exc:
                return _fail(f"event {sequence} is malformed: {exc}")
            expected_id = f"net-{launch_count + 1}"
            if event.get("net_id") != expected_id or event.get("origin") != list(contract["origin"]) or event.get("flight_ticks") != contract["flight_ticks"]:
                return _fail(f"event {sequence} projectile manifest disagrees with replay")
            projectile = {
                "id": expected_id,
                "age": 0,
                "origin10": (contract["origin"][0] * 10, contract["origin"][1] * 10),
                "aim10": (aim[0] * 10, aim[1] * 10),
                "x10": contract["origin"][0] * 10,
                "y10": contract["origin"][1] * 10,
            }
            nets -= 1
            launch_count += 1
            cooldown = contract["flight_ticks"]
            continue

        if kind == "tick":
            if not preview_complete or lure is None:
                return _fail(f"event {sequence} advances the hunt before the lure")
            if event.get("tick") != tick + 1:
                return _fail(f"event {sequence} clock tick is out of order")
            if tick >= requirements["time_limit_ticks"]:
                return _fail(f"event {sequence} advances beyond the observatory clock")
            tick += 1
            frozen_this_tick = freeze_active and freeze_energy > 0
            target_before = next(item for item in critters if item["id"] == target_id)
            target_vector = list(_lure_vector(target_before, lure))
            if frozen_this_tick:
                freeze_energy -= 1
                freeze_ticks += 1
            auto_release = bool(freeze_active and freeze_energy == 0)
            critters = [_step_critter(item, lure, frozen_this_tick, arena, contract["occluders"]) for item in critters]
            cooldown = max(0, cooldown - 1)
            resolution: dict[str, Any] | None = None
            if projectile is not None:
                projectile["age"] = int(projectile["age"]) + 1
                projectile["x10"], projectile["y10"] = _projectile_point(projectile, contract["flight_ticks"])
                radius = int(arena["creature_radius_x10"]) + int(arena["net_radius_x10"])
                radius_squared = radius * radius
                hit_id: str | None = None
                for critter in critters:
                    dx = int(projectile["x10"]) - int(critter["x10"])
                    dy = int(projectile["y10"]) - int(critter["y10"])
                    if dx * dx + dy * dy <= radius_squared:
                        hit_id = str(critter["id"])
                        break
                if hit_id is not None:
                    resolution = {"kind": "target" if hit_id == target_id else "decoy", "net_id": projectile["id"], "critter_id": hit_id}
                    target_hit_id = hit_id
                    if hit_id == target_id:
                        target_captured = True
                        target_resolution_count += 1
                        target_state = next(item for item in critters if item["id"] == target_id)
                        ritual_fault = not (
                            freeze_ticks >= requirements["minimum_freeze_ticks"]
                            and freeze_downs >= 1
                            and freeze_releases >= 1
                            and int(target_state.get("portal_count", 0)) >= requirements["target_portal_transitions"]
                            and int(target_state.get("occluded_ticks", 0)) >= requirements["target_occluded_ticks"]
                        )
                    else:
                        decoy_hits += 1
                    projectile = None
                elif int(projectile["age"]) >= contract["flight_ticks"]:
                    resolution = {"kind": "miss", "net_id": projectile["id"], "critter_id": None}
                    misses += 1
                    projectile = None
            if auto_release:
                freeze_active = False
            expected_fields = {
                "frozen": frozen_this_tick,
                "freeze_energy_after": freeze_energy,
                "freeze_ticks_used": freeze_ticks,
                "freeze_auto_released": auto_release,
                "target_lure_vector": target_vector,
                "critters": _snapshot(critters),
                "projectile": _projectile_public(projectile),
                "resolution": resolution,
                "nets_after": nets,
                "cooldown_after": cooldown,
            }
            for field, expected in expected_fields.items():
                if event.get(field) != expected:
                    return _fail(f"event {sequence} {field} disagrees with analytic replay")
            continue

        return _fail(f"event {sequence} has unknown kind {kind!r}")

    target_state = next(item for item in critters if item["id"] == target_id)
    expected_payload = {
        "final_tick": tick,
        "nets_remaining": nets,
        "freeze_energy_ticks": freeze_energy,
        "freeze_ticks_used": freeze_ticks,
        "lure": [lure[0] // 10, lure[1] // 10] if lure else None,
        "target_captured": target_captured,
        "target_hit_id": target_hit_id,
        "decoy_hits": decoy_hits,
        "misses": misses,
        "reset_count": reset_count,
        "preview_count": preview_count,
        "final_critters": _snapshot(critters),
        "projectile": _projectile_public(projectile),
        "target_portal_transitions": int(target_state.get("portal_count", 0)),
        "target_occluded_ticks": int(target_state.get("occluded_ticks", 0)),
    }
    for field, expected in expected_payload.items():
        if payload.get(field) != expected:
            return _fail(f"submitted {field} does not match interception replay")

    passed = (
        payload.get("completed") is True
        and target_captured
        and target_hit_id == target_id
        and target_resolution_count == 1
        and lure is not None
        and freeze_ticks >= requirements["minimum_freeze_ticks"]
        and freeze_downs >= 1
        and freeze_releases >= 1
        and int(target_state.get("portal_count", 0)) >= requirements["target_portal_transitions"]
        and int(target_state.get("occluded_ticks", 0)) >= requirements["target_occluded_ticks"]
        and launch_count >= 1
        and not ritual_fault
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"observatory replay: nets launched {launch_count}; decoys {decoy_hits}; misses {misses}; "
            f"freeze {freeze_ticks}/{requirements['minimum_freeze_ticks']} ticks; target portals "
            f"{int(target_state.get('portal_count', 0))}/{requirements['target_portal_transitions']}; "
            f"cover ticks {int(target_state.get('occluded_ticks', 0))}/{requirements['target_occluded_ticks']}; "
            f"capture={'target' if target_hit_id == target_id else 'none'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "target_id": ground_truth.get("target_id"),
        "lure": ground_truth.get("solver_lure"),
        "freeze_ticks": ground_truth.get("solver_freeze_ticks"),
        "intercepts": ground_truth.get("solver_plans"),
        "instruction": "Place the listed lure, hold F for the listed ticks, release, then launch at a future intercept window rather than the current familiar position.",
        "answers": [],
    }
