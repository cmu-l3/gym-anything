from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "recursive_dollhouse_smuggling"


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).digest()[:8], "big")


def _view(view_id: str, index: int, mirror: int, rng: random.Random) -> dict[str, Any]:
    sx = (1.34, 1.53, 1.72)[index] + rng.uniform(-0.025, 0.025)
    sy = (0.58, 0.67, 0.76)[index] + rng.uniform(-0.012, 0.012)
    origin = [175 + rng.randint(-3, 3), 66 + rng.randint(-3, 3)]
    return {
        "id": view_id, "index": index, "label": ("MINIATURE", "HUMAN", "GIANT")[index],
        "canvas": {"width": 350, "height": 400},
        "matrix": [[round(mirror * sx, 6), round(-mirror * sx, 6)], [round(sy, 6), round(sy, 6)]],
        "origin": origin, "z_axis": [0, round(-(10 + index * 2.5), 3)],
    }


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    mirror = rng.choice((-1, 1))
    palettes = (
        {"ink": "#171326", "paper": "#f2ead7", "mini": "#ffc65c", "human": "#80dfcb", "giant": "#a88dff", "danger": "#f06465"},
        {"ink": "#111d24", "paper": "#eee3cb", "mini": "#ef9f5e", "human": "#70d7f0", "giant": "#c894ff", "danger": "#ef596f"},
        {"ink": "#22151c", "paper": "#f5e8d0", "mini": "#f5d36b", "human": "#83e3b7", "giant": "#aa92ff", "danger": "#ff705f"},
    )
    palette = rng.choice(palettes)
    views = [_view(view_id, index, mirror, rng) for index, view_id in enumerate(("mini", "human", "giant"))]
    walls = [
        {"id": "corridor-cap", "center": [25, 39], "size": [40, 4], "height": 4},
        {"id": "corridor-rail", "center": [25, 61], "size": [40, 4], "height": 5},
        {"id": "central-block", "center": [58, 44], "size": [8, 8], "height": 7},
        {"id": "scale-spire", "center": [60, 21], "size": [5, 18], "height": 10},
    ]
    gate = {"id": "gate", "center": [28, 50], "size": [6, 16], "height": 6, "movable_in_view": "giant"}
    portals = [
        {"id": "frame-mini-human", "from_scale": 0, "to_scale": 1, "center": [40, 50], "size": [11, 13]},
        {"id": "frame-human-giant", "from_scale": 1, "to_scale": 2, "center": [68, 34], "size": [12, 12]},
    ]
    parcel = {
        "id": "parcel", "initial_center": [12, 50], "initial_scale": 0,
        "sizes": [[4, 3], [6, 4], [9, 6]], "height_by_scale": [2.5, 4, 7],
    }
    parking = {"id": "gate-parking", "center": [18, 23], "size": [13, 20]}
    bay = {"id": "giant-bay", "scale": 2, "center": [88, 18], "size": [15, 14]}
    task_id = str(task.get("id") or "recursive_dollhouse_smuggling_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym", "mechanic_id": MECHANIC_ID, "task_id": task_id, "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Move the parcel through the nested rooms and deliver it at the correct scale.",
        "submit_label": "SEAL NESTED MANIFEST", "room": {"width": 100, "depth": 70}, "views": views,
        "palette": palette, "walls": walls, "gate": gate, "parking": parking, "portals": portals, "parcel": parcel, "bay": bay,
        "requirements": {"max_screen_step": 540, "inverse_tolerance": 0.12, "collision_substep": 0.8, "parking_tolerance": 3.5, "required_views": ["mini", "human", "giant"]},
        "clearance_audit": {"corridor_width": 18, "mini_parcel_clearance": 6, "portal_fit_margin": 3, "gate_exit_clearance": 1, "bay_fit_margin": 3},
        "generator": {"name": "canonical_recursive_isometric_room_v1", "variant_count": 10_800_000_000},
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
    }
    truth = {**public, "seed": seed, "mirror": mirror,
             "solver_waypoints": {"gate": [[49, 50], [49, 25], [18, 23]], "scale_0": [[40, 50]], "scale_1": [[49, 50], [49, 35], [68, 35], [68, 34]], "scale_2": [[75, 36], [84, 29], [88, 18]]}}
    for view in views:
        determinant = view["matrix"][0][0] * view["matrix"][1][1] - view["matrix"][0][1] * view["matrix"][1][0]
        assert abs(determinant) > 1.4
    assert parcel["sizes"][0][0] < portals[0]["size"][0] and parcel["sizes"][2][0] < bay["size"][0]
    return public, truth
