from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "wonky_text_hostile_rendering"
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def _delta(a: float, b: float) -> float:
    return abs((a - b + 180.0) % 360.0 - 180.0)


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    token = "".join(rng.choice(ALPHABET) for _ in range(5))
    plates = []
    for index, color in enumerate(("cyan", "magenta", "amber")):
        target = rng.randrange(0, 360, 5)
        initial = rng.randrange(0, 360, 5)
        while _delta(initial, target) < 55:
            initial = rng.randrange(0, 360, 5)
        plates.append({
            "id": f"plate-{index}",
            "color": color,
            "target": target,
            "initial": initial,
            "harmonic": rng.choice((2, 3, 4)),
            "warp": round(rng.uniform(14, 24), 2),
        })
    contract = {"token": token, "plates": plates, "tolerance": 7.5, "degrees_per_pixel": 0.62, "max_drag_delta": 180}
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "Register the plate.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "anamorphic_registration_press_v2", "variant_count": len(ALPHABET)**5 * 72**3},
        "press": contract,
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "press": contract,
    }
    return public, truth
