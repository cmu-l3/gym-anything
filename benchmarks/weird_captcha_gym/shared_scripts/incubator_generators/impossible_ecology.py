from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "impossible_ecology"
PROBES = ("CLIMATE", "FOOD", "LIGHT")
TICKS_PER_CYCLE = 8
STAGE_WIDTH = 1000
STAGE_HEIGHT = 460
LAW_VARIANTS = {
    "CLIMATE": ("thermal_stasis", "inverse_thermotaxis"),
    "FOOD": ("food_avoidance", "runaway_growth"),
    "LIGHT": ("negative_phototaxis", "light_freeze"),
}


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def _normal_frame(probe: str, tick: int) -> tuple[int, int, int, int, int]:
    if probe == "LIGHT":
        return 50 + 3 * tick, 54, 100, 52 + 3 * tick, 8
    if probe == "CLIMATE":
        return 50 + (tick % 2), 54 - tick // 3, 100 + tick // 4, 48 + 5 * tick, -4
    return 50 + tick, 54 - 2 * tick, 100 + 4 * tick, 54 + tick, 3


def _anomalous_frame(probe: str, law: str, tick: int) -> tuple[int, int, int, int, int]:
    if law == "negative_phototaxis":
        return 50 - 3 * tick, 54, 100, 52 + tick, -12
    if law == "light_freeze":
        return 50, 54, 100, 42, 0
    if law == "thermal_stasis":
        return 50, 54, 100, 48, 0
    if law == "inverse_thermotaxis":
        return 50 - (tick % 2), 54 + tick // 2, 98, 48 - 3 * tick, 7
    if law == "food_avoidance":
        return 50 - 2 * tick, 54 + tick, 100 - 2 * tick, 49, -10
    return 50 + tick, 54 - tick, 100 + 9 * tick, 64 + 2 * tick, 14


def _snapshot(habitat_ids: list[str], culprit_id: str, probe: str, anomaly_probe: str, law: str, tick: int) -> list[dict[str, Any]]:
    snapshot: list[dict[str, Any]] = []
    for habitat_id in habitat_ids:
        values = (
            _anomalous_frame(probe, law, tick)
            if habitat_id == culprit_id and probe == anomaly_probe
            else _normal_frame(probe, tick)
        )
        x, y, scale, pulse, lean = values
        snapshot.append({
            "habitat_id": habitat_id,
            "x": x,
            "y": y,
            "scale": scale,
            "pulse": pulse,
            "lean": lean,
        })
    return snapshot


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    protocol = list(PROBES)
    rng.shuffle(protocol)
    habitat_ids = [f"habitat-{index + 1}" for index in range(5)]
    culprit_id = rng.choice(habitat_ids)
    anomaly_probe = rng.choice(PROBES)
    response_law = rng.choice(LAW_VARIANTS[anomaly_probe])
    palette = rng.choice(("moss", "brine", "ember", "violet"))

    habitats = []
    habitat_rects: list[dict[str, Any]] = []
    for index, habitat_id in enumerate(habitat_ids):
        x = 14 + index * 194
        rect = {"id": habitat_id, "x": x, "y": 20, "width": 178, "height": 278}
        habitat_rects.append(rect)
        habitats.append({
            "id": habitat_id,
            "label": f"BIO-{chr(65 + index)}{rng.randint(10, 99)}",
            "rect": rect,
        })

    cycles: list[dict[str, Any]] = []
    for step, probe in enumerate(protocol):
        frames = [
            {"tick": tick, "snapshot": _snapshot(habitat_ids, culprit_id, probe, anomaly_probe, response_law, tick)}
            for tick in range(1, TICKS_PER_CYCLE + 1)
        ]
        cycles.append({"step": step, "probe": probe, "frames": frames})

    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "impossible_ecology_seed_0001@0.1")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Run the posted three-probe protocol, observe every full response cycle, then quarantine the organism that breaks the causal law.",
        "submit_label": "CERTIFY QUARANTINE",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {
            "name": "causal_terrarium_lab_v1",
            "variant_count": 5 * 3 * 2 * 6 * 4 * 90**5,
        },
        "palette": palette,
        "stage": {"width": STAGE_WIDTH, "height": STAGE_HEIGHT},
        "habitats": habitats,
        "habitat_rects": habitat_rects,
        "quarantine_rect": {"x": 330, "y": 338, "width": 340, "height": 102},
        "protocol": protocol,
        "ticks_per_cycle": TICKS_PER_CYCLE,
        "tick_ms": 115,
        "cycles": cycles,
        "rules": [
            "Initial appearance is not evidence.",
            "Run the illuminated protocol in order and let every response cycle finish.",
            "After all three trials, drag the causal violator into quarantine.",
        ],
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "protocol": protocol,
        "ticks_per_cycle": TICKS_PER_CYCLE,
        "cycles": cycles,
        "habitat_rects": habitat_rects,
        "quarantine_rect": public_state["quarantine_rect"],
        "culprit_id": culprit_id,
        "anomaly_probe": anomaly_probe,
        "response_law": response_law,
        "variant_count": public_state["generator"]["variant_count"],
    }
    assert len(protocol) == 3 and set(protocol) == set(PROBES)
    assert len(cycles) == 3 and all(len(cycle["frames"]) == TICKS_PER_CYCLE for cycle in cycles)
    return public_state, ground_truth
