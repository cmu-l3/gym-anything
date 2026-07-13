from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "temporal_memory_first_change"


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    glyphs = rng.sample(["△", "○", "□", "◇", "✦", "⌁", "⊙", "⬡", "✣", "◐"], 7)
    objects = []
    for index in range(7):
        objects.append({
            "id": f"tracker-{hashlib.sha256(f'{seed}|tracker|{index}'.encode()).hexdigest()[:8]}",
            "glyph": glyphs[index],
            "x0": 80 + index * 88 + rng.randint(-16, 16),
            "y0": rng.randint(92, 250),
            "amp_x": rng.randint(38, 76),
            "amp_y": rng.randint(28, 62),
            "rate_x": round(rng.uniform(0.00055, 0.0009), 7),
            "rate_y": round(rng.uniform(0.00048, 0.00082), 7),
            "phase": round(rng.uniform(0, math.tau), 6),
        })
    first_change_ms = rng.randrange(3200, 4300, 100)
    # Occluders are a tracking burden, never a random impossibility at the scored event.
    def event_x(item: dict[str, Any]) -> float:
        return float(item["x0"]) + math.sin(float(item["phase"]) + first_change_ms * float(item["rate_x"])) * float(item["amp_x"])

    visible = [
        item for item in objects
        if not any(left - 30 <= event_x(item) <= right + 30 for left, right in ((248, 302), (492, 548)))
    ]
    target = rng.choice(visible or objects)
    decoys = [item for item in objects if item["id"] != target["id"]]
    rng.shuffle(decoys)
    events = [{"object_id": target["id"], "at_ms": first_change_ms, "duration_ms": 520, "kind": "first"}]
    for index, item in enumerate(decoys[:4]):
        events.append({"object_id": item["id"], "at_ms": first_change_ms + 850 + index * 620, "duration_ms": 440, "kind": "decoy"})
    settle_order = [item["id"] for item in objects]
    rng.shuffle(settle_order)
    contract = {
        "stage": {"width": 700, "height": 330},
        "objects": objects,
        "events": events,
        "first_change_ms": first_change_ms,
        "pulse_lead_ms": 850,
        "lens_radius": 68,
        "settle_ms": first_change_ms + 3900,
        "settle_order": settle_order,
    }
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "Find the first change. Mark its carrier after the field settles.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "active_transient_tracking_v2", "variant_count": 7 * 5040 * 10**6},
        "timeline": contract,
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "target_object_id": target["id"],
        "timeline": contract,
    }
    return public, truth
