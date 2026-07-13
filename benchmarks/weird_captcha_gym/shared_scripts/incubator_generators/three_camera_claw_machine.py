from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "three_camera_claw_machine"


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed)); mirror = rng.choice((-1, 1))
    palettes = (
        {"cage": "#2a2c2f", "feed": "#d7ead0", "artifact": "#f3a447", "claw": "#d64c43", "chute": "#60c7a0"},
        {"cage": "#202c35", "feed": "#cce7e1", "artifact": "#ffb35c", "claw": "#ef626c", "chute": "#5ac4d8"},
        {"cage": "#342b28", "feed": "#e7ddc4", "artifact": "#eaa645", "claw": "#d84d63", "chute": "#70c497"},
    )
    palette = rng.choice(palettes)
    target_center = [round((2.35 + rng.choice((-.15, 0, .15))) * mirror, 3), .95, round(1.8 + rng.choice((-.2, 0, .2)), 3)]
    objects = [
        {"id": "artifact-a", "center": target_center, "radius": .43, "marked": True, "color": palette["artifact"]},
        {"id": "artifact-b", "center": [round((-2.3 + rng.choice((-.2, 0, .2))) * mirror, 3), .9, 1.8], "radius": .43, "marked": False, "color": "#7c91a3"},
        {"id": "artifact-c", "center": [round(2.15 * mirror, 3), .9, round(-1.35 + rng.choice((-.2, 0, .2)), 3)], "radius": .43, "marked": False, "color": "#8b7aa1"},
    ]
    obstacles = [
        {"id": "crossbar", "center": [0, 2.55, round(.15 + rng.choice((-.15, 0, .15)), 3)], "half": [2.15, .38, .5]},
        {"id": "post", "center": [round(-1.15 * mirror, 3), 2.05, round(-1.55 + rng.choice((-.15, 0, .15)), 3)], "half": [.42, 1.55, .42]},
        {"id": "baffle", "center": [round(2.8 * mirror, 2), 2.0, round(-.35 + rng.choice((-.15, 0, .15)), 3)], "half": [.38, 1.35, 1.0]},
    ]
    chute = {"center": [round((-3.65 + rng.choice((-.1, 0, .1))) * mirror, 3), 1.0, round(-3.55 + rng.choice((-.1, 0, .1)), 3)], "half": [.78, .8, .78]}
    camera_scale = rng.choice((20, 21, 22))
    cameras = {
        "top": {"matrix": [[camera_scale, 0, 0], [0, 0, camera_scale]], "origin": [170, 115], "delay": 0, "label": "OVERHEAD", "depth_axis": 1, "depth_sign": 1},
        "front": {"matrix": [[camera_scale, 0, 0], [0, -camera_scale, 0]], "origin": [170, 218], "delay": 2, "label": "FRONT", "depth_axis": 2, "depth_sign": -1},
        "side": {"matrix": [[0, 0, camera_scale], [0, -camera_scale, 0]], "origin": [170, 218], "delay": 4, "label": "SIDE", "depth_axis": 0, "depth_sign": -1},
    }
    world = {"bounds": {"x": [-5, 5], "y": [.45, 6], "z": [-5, 5]}, "claw_radius": .28, "tick_seconds": .12,
             "acceleration": rng.choice((.26, .28, .3)), "max_speed": .72, "damping": rng.choice((.8, .82, .84)), "collision_step": .06, "capture_distance": .78}
    initial = {"position": [0, 5.25, -3.85], "velocity": [0, 0, 0], "gripper": "open"}
    task_id = str(task.get("id") or "three_camera_claw_machine_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym", "mechanic_id": MECHANIC_ID, "task_id": task_id, "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Retrieve the marked artifact using only the three camera feeds.",
        "submit_label": "CERTIFY CCTV RETRIEVAL", "world": world, "initial": initial, "objects": objects,
        "obstacles": obstacles, "chute": chute, "cameras": cameras, "palette": palette,
        "requirements": {"max_ticks": 520, "max_events": 1300, "required_feeds": ["top", "front", "side"]},
        "generator": {"name": "staggered_cctv_inertial_cage_v1", "variant_count": 3_188_646,
                      "variant_count_kind": "2 mirrors × 3 palettes × twelve independent 3-way bounded layout/camera/dynamics choices"},
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "render_boundary": "The browser necessarily receives cage/object geometry and the marked visual flag used by CCTV rendering, so page internals can identify the target. It receives no safe waypoint route or privileged world-control action.",
    }
    safe_y = 5.25
    truth = {**public, "seed": seed, "mirror": mirror, "target_id": "artifact-a",
             "solver": {"target": target_center, "chute": chute["center"], "safe_y": safe_y}}
    for obstacle in obstacles:
        assert obstacle["center"][1] + obstacle["half"][1] + world["claw_radius"] < safe_y
    assert math.dist(target_center, chute["center"]) > 4
    return public, truth
