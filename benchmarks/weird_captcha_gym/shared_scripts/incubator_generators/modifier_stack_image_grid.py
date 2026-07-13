from __future__ import annotations

import copy
import hashlib
import random
from typing import Any


MECHANIC_ID = "modifier_stack_image_grid"
STAGE = {"width": 940, "height": 500}
VARIANT_COUNT = 31_000_000_000


MODIFIERS = {
    "rotate": ((45, -45), (90, -90)),
    "slice": ((28, -28), (38, -38)),
    "scale": ((75, 133), (125, 80)),
    "mirror": ((1, 1),),
}


def _public_artifact(artifact: dict[str, Any]) -> dict[str, Any]:
    public = copy.deepcopy(artifact)
    for token in public["stack"]:
        token.pop("inverse", None)
    return public


def _seed(seed: str) -> int:
    return int(hashlib.sha256(f"{seed}|{MECHANIC_ID}|restoration-v2".encode()).hexdigest()[:16], 16)


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    task_id = str(task.get("id") or "modifier_stack_image_grid_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:13]
    kinds = ["gear", "signal_kite", "forked_key"]
    rng.shuffle(kinds)
    artifacts: list[dict[str, Any]] = []
    for round_index, artifact_kind in enumerate(kinds):
        modifier_kinds = rng.sample(tuple(MODIFIERS), 3)
        stack: list[dict[str, Any]] = []
        for stack_index, modifier_kind in enumerate(modifier_kinds):
            applied, inverse = rng.choice(MODIFIERS[modifier_kind])
            stack.append({
                "id": f"mod-{hashlib.sha256(f'{seed}|{round_index}|{stack_index}'.encode()).hexdigest()[:7]}",
                "kind": modifier_kind,
                "applied": applied,
                "inverse": inverse,
                "sequence": stack_index,
            })
        rack_order = [item["id"] for item in stack]
        rng.shuffle(rack_order)
        rack_rects = [
            {"token_id": token_id, "x": 205 + rack_index * 190, "y": 234, "width": 150, "height": 56}
            for rack_index, token_id in enumerate(rack_order)
        ]
        artifacts.append({
            "id": f"artifact-{hashlib.sha256(f'{seed}|artifact|{round_index}'.encode()).hexdigest()[:7]}",
            "sequence": round_index,
            "kind": artifact_kind,
            "ink": rng.choice(("#f0ce72", "#75d9d3", "#e996b4")),
            "stack": stack,
            "rack_order": rack_order,
            "rack_rects": rack_rects,
            "playback_ms": 3150,
            "replay_limit": 1,
        })
    rail = {
        "start": [118, 414],
        "end": [822, 414],
        "gate_x": [310, 510, 710],
        "half_height": 34,
    }
    slots = [
        {"index": index, "x": 252 + index * 190, "y": 324, "width": 142, "height": 60}
        for index in range(3)
    ]
    requirements = {
        "minimum_chip_moves": 4,
        "minimum_chip_drag_ms": 80,
        "minimum_rail_samples": 24,
        "minimum_rail_ms": 680,
        "maximum_rail_step": 54,
        "playback_minimum_ms": 2900,
        "maximum_event_time_ms": 240_000,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": "Watch each corruption stack. Build its inverse in reverse order, then pull the artifact through without breaking contact.",
        "submit_label": "STAMP RESTORATION LOG",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "kinetic_modifier_restoration_press_v2", "variant_count": VARIANT_COUNT},
        "stage": STAGE,
        "artifacts": [_public_artifact(artifact) for artifact in artifacts],
        "rail": rail,
        "slots": slots,
        "requirements": requirements,
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": STAGE,
        "artifacts": copy.deepcopy(artifacts),
        "rail": rail,
        "slots": slots,
        "requirements": requirements,
        "variant_count": VARIANT_COUNT,
    }
    for artifact in artifacts:
        assert len(artifact["stack"]) == 3 and len(set(artifact["rack_order"])) == 3
    return public_state, ground_truth
