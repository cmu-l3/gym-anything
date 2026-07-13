from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "slime_commute"


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    lane_templates = [
        (9, "road", 0.045, 0.82, [0.0, 3.2, 6.4]),
        (8, "road", -0.036, 1.05, [1.1, 5.4]),
        (6, "water", 0.026, 2.35, [0.1, 3.25, 6.35]),
        (5, "water", -0.021, 2.7, [1.0, 5.0, 8.1]),
        (3, "rail", 0.082, 1.65, [1.0, 6.5]),
        (2, "road", -0.048, 0.9, [0.4, 3.7, 7.0]),
    ]
    lanes = []
    for row, kind, speed, length, offsets in lane_templates:
        phase = round(rng.uniform(0, 9), 4)
        if rng.choice((False, True)):
            speed *= -1
        lanes.append({
            "row": row,
            "kind": kind,
            "speed": round(speed, 4),
            "length": length,
            "offsets": offsets,
            "phase": phase,
        })
    start_x, goal_x = rng.randrange(2, 7), rng.randrange(1, 8)
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    board = {
        "columns": 9,
        "rows": 11,
        "start_x": start_x,
        "goal_x": goal_x,
        "lanes": lanes,
        "tick_ms": 100,
        # 44 px avatar on a 720 px / 9-column field: the visible body and
        # independent replay collider are the same 0.275-cell radius.
        "player_radius": 0.275,
        "max_deaths": 4,
        "max_ticks": 2400,
        "hop_cooldown_ticks": 2,
    }
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "Get home.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "fixed_step_crossing_v2", "variant_count": 9**8},
        "board": board,
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "board": board,
    }
    return public, truth
