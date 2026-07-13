from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "semantic_drag_drop_absurdity"
SIGNATURES = (
    {"thermal": "bloom", "polarity": "left"},
    {"thermal": "bloom", "polarity": "right"},
    {"thermal": "contract", "polarity": "left"},
    {"thermal": "contract", "polarity": "right"},
)


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}|v2".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    signatures = [dict(item) for item in SIGNATURES]
    rng.shuffle(signatures)
    objects = []
    receivers = []
    expected = {}
    glyphs = rng.sample(["△", "○", "◇", "□", "⌁", "✦", "⊙", "⬡"], 8)
    for index, signature in enumerate(signatures):
        object_id = f"specimen-{hashlib.sha256(f'{seed}|specimen|{index}'.encode()).hexdigest()[:8]}"
        receiver_id = f"receiver-{hashlib.sha256(f'{seed}|receiver|{index}'.encode()).hexdigest()[:8]}"
        objects.append({
            "id": object_id,
            "glyph": glyphs[index],
            "runtime_signature": signature,
            "x": 44 + (index % 2) * 126 + rng.randint(-6, 6),
            "y": 64 + (index // 2) * 118 + rng.randint(-6, 6),
        })
        receivers.append({
            "id": receiver_id,
            "glyph": glyphs[index + 4],
            "signature": signature,
            "x": 424 + (index % 2) * 126 + rng.randint(-6, 6),
            "y": 58 + (index // 2) * 118 + rng.randint(-6, 6),
        })
        expected[object_id] = receiver_id
    rng.shuffle(objects)
    rng.shuffle(receivers)
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|challenge".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": "Probe the specimens. Route each response to its twin.",
        "asset_manifest": "shared_runtime/assets/provenance/reviewed_overhaul_v1.json",
        "generator": {"name": "causal_probe_lab_v2", "variant_count": 24 * 40320 * 4096},
        "objects": objects,
        "receivers": receivers,
        "probe_hold_ms": 420,
        "response_ms": 950,
    }
    truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "expected_assignments": expected,
        "signatures": {item["id"]: item["runtime_signature"] for item in objects},
    }
    return public, truth
