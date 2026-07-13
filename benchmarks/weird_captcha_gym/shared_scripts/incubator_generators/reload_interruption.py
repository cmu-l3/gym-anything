from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "reload_interruption"
DIRECTIONS = ("up", "right", "down", "left")


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    sequence = []
    while len(sequence) < 7:
        candidate = rng.choice(DIRECTIONS)
        if not sequence or candidate != sequence[-1]:
            sequence.append(candidate)
    interruptions = []
    for index, after_step in enumerate((2, 5)):
        interruptions.append({
            "id": f"overload-{hashlib.sha256(f'{seed}|overload|{index}'.encode()).hexdigest()[:8]}",
            "after_step": after_step,
            "center": [350 + rng.randint(-24, 24), 190 + rng.randint(-18, 18)],
            "radius_x": rng.randint(105, 138),
            "radius_y": rng.randint(58, 86),
            "phase": round(rng.uniform(0, math.tau), 5),
            "rate": round(rng.uniform(0.0048, 0.0062), 6),
            "hold_ms": 1150,
            "tolerance": 42,
            "min_samples": 10,
            "max_gap_ms": 180,
        })
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "Reload the mechanism.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "interrupted_gesture_memory_v2", "variant_count": 4**7 * 2048},
        "sequence": sequence,
        "interruptions": interruptions,
        "preview_step_ms": 420,
        "max_gesture_step": 180,
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "sequence": sequence,
        "interruptions": interruptions,
        "max_gesture_step": 180,
    }
    return public, truth
