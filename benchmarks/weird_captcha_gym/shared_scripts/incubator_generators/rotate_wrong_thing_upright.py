from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "rotate_wrong_thing_upright"


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    def angle() -> int:
        value = rng.randrange(-115, 116, 5)
        return value if abs(value) >= 30 else value + (45 if value >= 0 else -45)
    initial = {"outer": angle(), "middle": angle(), "inner": angle()}
    views = rng.sample(["front", "side", "top"], 3)
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    contract = {
        "initial": initial,
        "target": {"outer": 0.0, "middle": 0.0, "inner": 0.0},
        "tolerance": 6.0,
        "views": views,
        "degrees_per_pixel": 0.42,
        "max_drag_delta": 180,
        "coupling": {"outer_to_inner": 0.17, "middle_to_outer": -0.13, "inner_to_middle": 0.11},
    }
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "Bring the inner mark into world plumb.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "tri_axis_gimbal_v2", "variant_count": 47**3 * 6},
        "gimbal": contract,
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "gimbal": contract,
    }
    return public, truth
