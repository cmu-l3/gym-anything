from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "consequences_boss"
SCENES = (
    ("lantern", "✦"),
    ("seed", "❋"),
    ("moth", "◈"),
    ("root", "⌁"),
    ("mirror", "◇"),
)


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    palette = ["ember", "violet", "moss", "azure", "ivory"]
    rng.shuffle(palette)
    scenes = []
    for index, (kind, glyph) in enumerate(SCENES):
        scene_id = f"covenant-{hashlib.sha256(f'{seed}|{kind}'.encode()).hexdigest()[:9]}"
        scenes.append({
            "id": scene_id,
            "kind": kind,
            "glyph": glyph,
            "color": palette[index],
            "socket_glyphs": rng.sample(["◐", "◒", "△", "▽", "⊂", "⊃"], 2),
            "initial_seal": rng.randrange(4),
        })
    boss_order = [scene["id"] for scene in scenes]
    rng.shuffle(boss_order)
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "Make five covenants. Rebuild them when judgment returns.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "covenant_reconstruction_v2", "variant_count": 5 * 8 * 8 * 24},
        "scenes": scenes,
        "boss_order": boss_order,
        "storm_ms": 1500,
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "scene_ids": [scene["id"] for scene in scenes],
        "boss_order": boss_order,
        "storm_ms": 1500,
    }
    return public, truth
