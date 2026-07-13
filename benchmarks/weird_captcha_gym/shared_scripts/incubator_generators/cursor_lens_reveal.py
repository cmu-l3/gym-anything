from __future__ import annotations

import copy
import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "cursor_lens_reveal"
STAGE = {"width": 920, "height": 500}
VARIANT_COUNT = 22_400_000_000


def _seed(seed: str) -> int:
    return int(hashlib.sha256(f"{seed}|{MECHANIC_ID}|palimpsest-v2".encode()).hexdigest()[:16], 16)


def _position(node: dict[str, Any], elapsed_ms: float) -> list[float]:
    motion = node["motion"]
    phase = float(motion["phase"])
    angle = math.tau * elapsed_ms / float(motion["period_ms"]) + phase
    return [
        round(float(node["base"][0]) + float(motion["radius_x"]) * math.sin(angle), 2),
        round(float(node["base"][1]) + float(motion["radius_y"]) * math.cos(angle * float(motion["ratio"])), 2),
    ]


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    task_id = str(task.get("id") or "cursor_lens_reveal_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:13]
    bases = [[128, 122], [735, 104], [474, 216], [180, 392], [742, 390]]
    rng.shuffle(bases)
    polarizations: list[int] = []
    for _ in range(5):
        choices = [value for value in (0, 45, 90, 135) if not polarizations or value != polarizations[-1]]
        polarizations.append(rng.choice(choices))
    nodes: list[dict[str, Any]] = []
    glyphs = list("◇△⊕⌁✦")
    rng.shuffle(glyphs)
    for index, base in enumerate(bases):
        node = {
            "id": f"echo-{hashlib.sha256(f'{seed}|echo|{index}'.encode()).hexdigest()[:7]}",
            "sequence": index,
            "base": base,
            "polarization_deg": polarizations[index],
            "glyph": glyphs[index],
            "motion": {
                "radius_x": rng.randint(14, 27),
                "radius_y": rng.randint(10, 22),
                "period_ms": rng.randint(5400, 7600),
                "phase": round(rng.uniform(0, math.tau), 4),
                "ratio": rng.choice((0.68, 0.82, 1.14)),
            },
        }
        nodes.append(node)
        for sample in range(0, 16_001, 250):
            x, y = _position(node, sample)
            assert 64 <= x <= STAGE["width"] - 64 and 58 <= y <= STAGE["height"] - 58
    clutter = [
        {
            "x": rng.randint(18, STAGE["width"] - 18),
            "y": rng.randint(18, STAGE["height"] - 18),
            "length": rng.randint(5, 24),
            "angle": rng.randint(0, 179),
            "phase": rng.random(),
        }
        for _ in range(145)
    ]
    requirements = {
        "lock_radius": 31,
        "polarization_tolerance_deg": 10,
        "minimum_hold_ms": 460,
        "minimum_track_samples": 4,
        "minimum_probe_samples": 32,
        "minimum_probe_cells": 14,
        "minimum_tuning_changes": 4,
        "maximum_event_time_ms": 180_000,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": "Tune the glass, catch each moving echo, and hold it steady before its trail decays.",
        "submit_label": "DEVELOP THE PLATE",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "polarized_moving_palimpsest_v2", "variant_count": VARIANT_COUNT},
        "stage": STAGE,
        "lens_radius": 72,
        "nodes": copy.deepcopy(nodes),
        "clutter": clutter,
        "requirements": requirements,
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": STAGE,
        "nodes": copy.deepcopy(nodes),
        "clutter": clutter,
        "requirements": requirements,
        "variant_count": VARIANT_COUNT,
    }
    assert len({node["id"] for node in nodes}) == 5
    return public_state, ground_truth
