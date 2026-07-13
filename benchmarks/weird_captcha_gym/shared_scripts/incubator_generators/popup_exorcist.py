from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "popup_exorcist"
THEMES = ("update", "coupon", "cleaner", "forecast", "player", "survey", "prize")


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    parasite_index = rng.randrange(1, 6)
    popups = []
    for index, theme in enumerate(THEMES):
        width, height = rng.randint(205, 270), rng.randint(126, 178)
        popup_id = f"window-{hashlib.sha256(f'{seed}|window|{index}'.encode()).hexdigest()[:8]}"
        popups.append({
            "id": popup_id,
            "theme": theme,
            "title": rng.choice(("SERVICE NOTICE", "BACKGROUND TASK", "DESKTOP MESSAGE", "SYSTEM ASSISTANT")),
            "x": rng.randint(18, 690 - width),
            "y": rng.randint(20, 365 - height),
            "w": width,
            "h": height,
            "z": index + 2,
            "runtime_behavior": "replicate" if index == parasite_index else "close",
        })
    rng.shuffle(popups)
    parasite_id = next(item["id"] for item in popups if item["runtime_behavior"] == "replicate")
    echo_ids = [f"echo-{hashlib.sha256(f'{seed}|echo|{index}'.encode()).hexdigest()[:9]}" for index in range(2)]
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "End the infestation.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "parasite_containment_v2", "variant_count": 7 * 5040 * 2048},
        "popups": popups,
        "echo_ids": echo_ids,
        # Wide enough for the center of every generated window to enter while
        # preserving the field's physical drag bounds.
        "containment": {"x": 530, "y": 292, "w": 160, "h": 88},
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "popup_ids": [item["id"] for item in popups],
        "parasite_id": parasite_id,
        "echo_ids": echo_ids,
        "containment": public["containment"],
    }
    return public, truth
