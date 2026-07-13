from __future__ import annotations

import copy
import hashlib
import random
from typing import Any


MECHANIC_ID = "board_game_captcha"
STAGE = {"width": 900, "height": 520}
VARIANT_COUNT = 14_800_000_000


def _seed(seed: str) -> int:
    return int(hashlib.sha256(f"{seed}|{MECHANIC_ID}|tilt-v2".encode()).hexdigest()[:16], 16)


def _mirror_point(point: list[float], mirror: bool) -> list[float]:
    return [STAGE["width"] - point[0], point[1]] if mirror else list(point)


def _mirror_rect(rect: dict[str, Any], mirror: bool) -> dict[str, Any]:
    if not mirror:
        return copy.deepcopy(rect)
    return {**rect, "x": STAGE["width"] - rect["x"] - rect["width"]}


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    task_id = str(task.get("id") or "board_game_captcha_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:13]
    mirror = rng.choice((False, True))
    start = _mirror_point([88, 438], mirror)
    goal = {"id": "goal-cup", "position": _mirror_point([824, 112], mirror), "radius": 28}
    switch_points = [[205, 392], [410, 208], [656, 350]]
    switch_colors = ("#ef6c72", "#f1c665", "#68d8c1")
    switches = [
        {"id": f"gate-{index + 1}", "sequence": index, "position": _mirror_point(point, mirror), "radius": 24, "color": switch_colors[index]}
        for index, point in enumerate(switch_points)
    ]
    walls = [
        {"id": "wall-a", "x": 292, "y": 270, "width": 28, "height": 250},
        {"id": "wall-b", "x": 534, "y": 0, "width": 28, "height": 300},
        {"id": "wall-c", "x": 708, "y": 210, "width": 24, "height": 165},
    ]
    walls = [_mirror_rect(wall, mirror) for wall in walls]
    hazards = [
        {"id": "well-1", "position": _mirror_point([250, 160], mirror), "radius": 20},
        {"id": "well-2", "position": _mirror_point([585, 445], mirror), "radius": 22},
        {"id": "well-3", "position": _mirror_point([720, 160], mirror), "radius": 18},
    ]
    waypoints = [[205, 392], [246, 215], [410, 208], [478, 340], [656, 350], [765, 392], [824, 112]]
    waypoints = [_mirror_point(point, mirror) for point in waypoints]
    physics = {
        "tick_ms": 50,
        "acceleration": 190.0,
        "friction": 0.958,
        "maximum_speed": 178.0,
        "bounce": 0.42,
        "ball_radius": 13.0,
    }
    requirements = {
        "minimum_ticks": 72,
        "minimum_control_changes": 8,
        "maximum_events": 6500,
        "maximum_event_time_ms": 300_000,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": "Tilt the live board. Roll through the three lamps in order, avoid the wells, then settle in the cup.",
        "submit_label": "CERTIFY THE RUN",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "deterministic_gyroscopic_tilt_board_v2", "variant_count": VARIANT_COUNT},
        "stage": STAGE,
        "theme": rng.choice(("oxidized_arcade", "night_fair", "municipal_lab")),
        "start": start,
        "goal": goal,
        "switches": switches,
        "walls": walls,
        "hazards": hazards,
        "physics": physics,
        "requirements": requirements,
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": STAGE,
        "start": start,
        "goal": goal,
        "switches": switches,
        "walls": walls,
        "hazards": hazards,
        "physics": physics,
        "requirements": requirements,
        "solver_waypoints": waypoints,
        "variant_count": VARIANT_COUNT,
    }
    assert [switch["sequence"] for switch in switches] == [0, 1, 2]
    return public_state, ground_truth
