from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "rorschach_fixed_rubric"
TOOLS = ("FOLD", "PRESSURE", "COOL")
TICKS_PER_CYCLE = 7
STAGE_WIDTH = 1000
STAGE_HEIGHT = 420
OBJECTIVES = {
    "retains_fold": "STAMP THE BLOT THAT RETAINS ITS FOLD AFTER RELEASE.",
    "symmetric_rebound": "STAMP THE BLOT THAT REBOUNDS SYMMETRICALLY AFTER PRESSURE.",
    "cooling_inversion": "STAMP THE BLOT WHOSE LOBE FLOW INVERTS UNDER COOLING.",
}


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def _normal_metrics(tool: str, tick: int, phase: int) -> dict[str, int]:
    if tool == "FOLD":
        fold = 72 - abs(4 - tick) * 16 if tick <= 4 else max(0, 60 - tick * 8)
        return {"left": 100 - tick, "right": 100 + tick, "fold": max(0, fold), "hue": phase, "flow": 8}
    if tool == "PRESSURE":
        return {"left": 100 - 3 * tick, "right": 100 + 3 * tick, "fold": 0, "hue": phase, "flow": 12}
    return {"left": 100 - tick, "right": 100 - tick, "fold": 0, "hue": phase + 4 * tick, "flow": 15}


def _signature_metrics(signature: str, tool: str, tick: int, phase: int) -> dict[str, int]:
    if signature == "retains_fold" and tool == "FOLD":
        return {"left": 96, "right": 104, "fold": min(84, 12 * tick), "hue": phase, "flow": 5}
    if signature == "symmetric_rebound" and tool == "PRESSURE":
        squeeze = max(72, 100 - 8 * min(tick, 4))
        rebound = 100 if tick >= 6 else squeeze
        return {"left": rebound, "right": rebound, "fold": 0, "hue": phase, "flow": 22}
    if signature == "cooling_inversion" and tool == "COOL":
        return {"left": 100 + 2 * tick, "right": 100 - 2 * tick, "fold": 0, "hue": (phase + 26 * tick) % 360, "flow": -10 - 3 * tick}
    return _normal_metrics(tool, tick, phase)


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    protocol = list(TOOLS)
    rng.shuffle(protocol)
    signature = rng.choice(tuple(OBJECTIVES))
    blot_ids = [f"blot-{index + 1}" for index in range(5)]
    culprit_id = rng.choice(blot_ids)
    blots = []
    blot_rects = []
    phases: dict[str, int] = {}
    for index, blot_id in enumerate(blot_ids):
        phase = rng.randrange(-12, 13)
        phases[blot_id] = phase
        rect = {"id": blot_id, "x": 20 + index * 192, "y": 24, "width": 172, "height": 250}
        blot_rects.append(rect)
        blots.append({
            "id": blot_id,
            "specimen": f"MAT-{rng.choice('ABCDEFGH')}{rng.randint(10, 99)}",
            "rect": rect,
            "visual_seed": rng.randrange(10_000),
        })

    cycles = []
    for step, tool in enumerate(protocol):
        frames = []
        for tick in range(1, TICKS_PER_CYCLE + 1):
            snapshot = []
            for blot_id in blot_ids:
                metrics = (
                    _signature_metrics(signature, tool, tick, phases[blot_id])
                    if blot_id == culprit_id
                    else _normal_metrics(tool, tick, phases[blot_id])
                )
                snapshot.append({"blot_id": blot_id, **metrics})
            frames.append({"tick": tick, "snapshot": snapshot})
        cycles.append({"step": step, "tool": tool, "frames": frames})

    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "rorschach_fixed_rubric_seed_0001@0.1")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or OBJECTIVES[signature],
        "objective": OBJECTIVES[signature],
        "submit_label": "CERTIFY MATERIAL STAMP",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "inkblot_material_interrogation_v1", "variant_count": 3_600_000_000},
        "stage": {"width": STAGE_WIDTH, "height": STAGE_HEIGHT},
        "blots": blots,
        "blot_rects": blot_rects,
        "stamp_dock_rect": {"x": 398, "y": 320, "width": 204, "height": 76},
        "protocol": protocol,
        "cycles": cycles,
        "ticks_per_cycle": TICKS_PER_CYCLE,
        "tick_ms": 105,
        "fold_min_distance": 190,
        "pressure_min_ms": 620,
        "rubric_labels": [
            "RETAINS FOLD: crease remains after release.",
            "SYMMETRIC REBOUND: paired lobes return together.",
            "COOLING INVERSION: lobe flow reverses sign under cooling.",
        ],
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "protocol": protocol,
        "cycles": cycles,
        "ticks_per_cycle": TICKS_PER_CYCLE,
        "stage": public_state["stage"],
        "blot_rects": blot_rects,
        "stamp_dock_rect": public_state["stamp_dock_rect"],
        "fold_min_distance": public_state["fold_min_distance"],
        "pressure_min_ms": public_state["pressure_min_ms"],
        "culprit_id": culprit_id,
        "signature": signature,
        "variant_count": public_state["generator"]["variant_count"],
    }
    assert len(blots) == 5 and len(cycles) == 3
    return public_state, ground_truth
