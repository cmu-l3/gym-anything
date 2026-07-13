from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "bureaucratic_signature_trap"


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    aperture = {"x": 356 + rng.randint(-22, 22), "y": 208 + rng.randint(-14, 14), "radius": 58}
    layers = []
    colors = ["cyan", "amber", "rose"]
    for index, color in enumerate(colors):
        target = {"x": rng.randint(-30, 30), "y": rng.randint(-22, 22)}
        initial = {"x": target["x"] + rng.choice((-1, 1)) * rng.randint(75, 135), "y": target["y"] + rng.choice((-1, 1)) * rng.randint(42, 82)}
        layers.append({
            "id": f"sheet-{hashlib.sha256(f'{seed}|sheet|{index}'.encode()).hexdigest()[:8]}",
            "color": color,
            "fragment": index,
            "initial": initial,
            "target": target,
        })
    contract = {
        "stage": {"width": 700, "height": 390},
        "aperture": aperture,
        "layers": layers,
        "alignment_tolerance": 10,
        "max_drag_step": 55,
        "signature": {"min_samples": 20, "min_length": 250, "max_step": 42, "closure": 38, "min_quadrants": 4},
    }
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "Countersign the concealed original.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "carbon_aperture_stack_v2", "variant_count": 10**8},
        "form": contract,
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "form": contract,
    }
    return public, truth
