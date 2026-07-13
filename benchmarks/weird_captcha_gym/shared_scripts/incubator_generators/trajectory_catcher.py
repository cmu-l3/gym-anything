from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "trajectory_catcher"
CANVAS_WIDTH = 900
CANVAS_HEIGHT = 480
FAMILIES = ("ballistic_arc", "sine_drift", "cubic_hook")
PALETTES = ("flight-recorder", "night-range", "oxide-plotter")
VARIANT_COUNT = 3**3 * 2**3 * 10_000_000_000


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _path(round_data: dict[str, Any], t_ms: float) -> tuple[float, float]:
    duration = float(round_data["duration_ms"])
    u = _clamp(t_ms / duration, 0.0, 1.0)
    travel = u if round_data["direction"] == "ltr" else 1.0 - u
    x = 70.0 + travel * 760.0
    base = float(round_data["base_y"])
    amplitude = float(round_data["amplitude"])
    wobble = float(round_data["wobble"])
    phase = float(round_data["phase"])
    if round_data["family"] == "ballistic_arc":
        y = base + amplitude * (4.0 * u * (1.0 - u) - 0.48) + wobble * math.sin(math.tau * u + phase)
    elif round_data["family"] == "sine_drift":
        y = base + amplitude * math.sin(math.tau * (u + phase)) + wobble * math.sin(6.0 * math.pi * u)
    else:
        centered = 2.0 * u - 1.0
        y = base + amplitude * (centered**3 - 0.34 * centered) + wobble * math.sin(4.0 * math.pi * u + phase)
    return x, y


def _velocity_angle(round_data: dict[str, Any], t_ms: float) -> float:
    before = _path(round_data, max(0.0, t_ms - 6.0))
    after = _path(round_data, min(float(round_data["duration_ms"]), t_ms + 6.0))
    return math.degrees(math.atan2(after[1] - before[1], after[0] - before[0])) % 360.0


def _local(point: tuple[float, float], catcher: dict[str, Any]) -> tuple[float, float]:
    radians = math.radians(float(catcher["angle_deg"]))
    cosine, sine = math.cos(radians), math.sin(radians)
    dx, dy = point[0] - float(catcher["x"]), point[1] - float(catcher["y"])
    return dx * cosine + dy * sine, -dx * sine + dy * cosine


def _angle_error(first: float, second: float) -> float:
    return abs((first - second + 90.0) % 180.0 - 90.0)


def _swept_catch(round_data: dict[str, Any], catcher: dict[str, Any]) -> tuple[bool, float | None]:
    if not catcher.get("armed"):
        return False, None
    start = float(round_data["wall_exit_ms"])
    end = float(round_data["duration_ms"])
    step = 10.0
    previous_t = start
    previous_local = _local(_path(round_data, previous_t), catcher)
    current_t = start + step
    while current_t <= end + 1e-6:
        current_local = _local(_path(round_data, current_t), catcher)
        crosses = previous_local[0] == 0 or current_local[0] == 0 or previous_local[0] * current_local[0] < 0
        if crosses:
            denominator = previous_local[0] - current_local[0]
            amount = 0.0 if abs(denominator) < 1e-9 else previous_local[0] / denominator
            amount = _clamp(amount, 0.0, 1.0)
            crossing_t = previous_t + (current_t - previous_t) * amount
            crossing_y = previous_local[1] + (current_local[1] - previous_local[1]) * amount
            clear_half_aperture = float(catcher["aperture"]) / 2.0 - float(round_data["projectile_radius"])
            if clear_half_aperture >= 0 and abs(crossing_y) <= clear_half_aperture + 1e-9 and _angle_error(_velocity_angle(round_data, crossing_t), float(catcher["angle_deg"])) <= float(round_data["alignment_tolerance_deg"]) + 1e-9:
                return True, crossing_t
        previous_t, previous_local = current_t, current_local
        current_t += step
    return False, None


def _round(rng: random.Random, seed: str, index: int, family: str) -> tuple[dict[str, Any], dict[str, Any]]:
    duration = rng.randrange(6000, 6601, 100)
    wall_enter = rng.randrange(1550, 1851, 50)
    wall_exit = rng.randrange(4300, min(4851, duration - 1150), 50)
    direction = rng.choice(("ltr", "rtl"))
    base_y = rng.randint(218, 262)
    amplitude = rng.randint(52, 78)
    wobble = rng.randint(11, 20)
    phase = round(rng.uniform(-0.42, 0.42), 3)
    projectile_radius = rng.randint(9, 13)
    round_data: dict[str, Any] = {
        "id": f"flight-{index + 1}-{hashlib.sha256(f'{seed}|flight|{index}'.encode()).hexdigest()[:5]}",
        "sequence": index,
        "family": family,
        "direction": direction,
        "duration_ms": duration,
        "wall_enter_ms": wall_enter,
        "wall_exit_ms": wall_exit,
        "minimum_observation_ms": 1_000,
        "commit_margin_ms": 180,
        "base_y": base_y,
        "amplitude": amplitude,
        "wobble": wobble,
        "phase": phase,
        "projectile_radius": projectile_radius,
        "alignment_tolerance_deg": 22,
        "initial_catcher": {"x": 450.0, "y": 427.0, "angle_deg": 0, "aperture": 70},
        "aperture_min": 60,
        "aperture_max": 120,
        "aperture_step": 10,
        "rotation_step_deg": 15,
        "replay_limit": 1,
    }
    enter_x = _path(round_data, wall_enter)[0]
    exit_x = _path(round_data, wall_exit)[0]
    round_data["wall"] = {
        "x": round(min(enter_x, exit_x) - 24, 2),
        "width": round(abs(exit_x - enter_x) + 48, 2),
        "y": 18,
        "height": CANVAS_HEIGHT - 36,
    }
    catch_time = min(duration - 520, wall_exit + rng.randrange(520, 801, 40))
    catch_x, catch_y = _path(round_data, catch_time)
    tangent = _velocity_angle(round_data, catch_time)
    angle = int(round(tangent / 15.0) * 15) % 180
    aperture = rng.choice((80, 90, 100, 110))
    solution = {
        "x": round(catch_x, 2),
        "y": round(catch_y, 2),
        "angle_deg": angle,
        "aperture": aperture,
        "catch_time_ms": catch_time,
    }
    solved = {**solution, "armed": True}
    caught, actual_time = _swept_catch(round_data, solved)
    if not caught:
        raise RuntimeError("generated catcher solution does not intersect the swept flight")
    solution["actual_crossing_ms"] = round(float(actual_time), 2)
    safe_initials = (
        round_data["initial_catcher"],
        {"x": 450.0, "y": 52.0, "angle_deg": 0, "aperture": 70},
        {"x": 82.0, "y": 430.0, "angle_deg": 90, "aperture": 60},
        {"x": 818.0, "y": 54.0, "angle_deg": 90, "aperture": 60},
    )
    round_data["initial_catcher"] = next(
        candidate for candidate in safe_initials
        if not _swept_catch(round_data, {**candidate, "armed": True})[0]
    )
    return round_data, solution


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "trajectory_catcher_seed_0001@0.1")
    families = list(FAMILIES)
    rng.shuffle(families)
    rounds: list[dict[str, Any]] = []
    solutions: list[dict[str, Any]] = []
    for index, family in enumerate(families):
        generated, solution = _round(rng, seed, index, family)
        rounds.append(generated)
        solutions.append({"round_id": generated["id"], **solution})
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt": task.get("natural_language") or "Watch each flight. Set, orient, size, and arm the catcher before emergence.",
        "generator": {"name": "analytic_hidden_flight_catcher_v1", "variant_count": VARIANT_COUNT},
        "range_id": f"TR-{challenge_id[:4].upper()}-{rng.randint(100, 999)}",
        "palette": rng.choice(PALETTES),
        "canvas": {"width": CANVAS_WIDTH, "height": CANVAS_HEIGHT},
        "rounds": rounds,
        "round_count": 3,
        "submit_label": "FILE FLIGHT LOG",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "canvas": public_state["canvas"],
        "rounds": rounds,
        "solutions": solutions,
        "round_count": 3,
        "variant_count": VARIANT_COUNT,
    }
    for round_data, solution in zip(rounds, solutions):
        for sample in range(0, int(round_data["duration_ms"]) + 1, 25):
            x, y = _path(round_data, sample)
            assert 40 <= x <= CANVAS_WIDTH - 40 and 42 <= y <= CANVAS_HEIGHT - 42
        assert round_data["wall_exit_ms"] - round_data["wall_enter_ms"] >= 2_400
        assert solution["catch_time_ms"] > round_data["wall_exit_ms"]
        assert _swept_catch(round_data, {**solution, "armed": True})[0]
        assert not _swept_catch(round_data, {**round_data["initial_catcher"], "armed": True})[0]
    return public_state, ground_truth
