from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "single_scene_split_boxes"
PALETTES = ("abyssal_cyan", "ember_violet", "acid_noir", "polar_signal")
MOTIFS = ("orbital_marsh", "night_freight", "glass_reef", "signal_dunes")
PHASE_TICKS = (-4, -3, -2, -1, 0, 1, 2, 3, 4)
VARIANT_COUNT = 7_431_782_400


def _tile_id(seed: str, source_index: int) -> str:
    return f"shard-{hashlib.sha256(f'{seed}|tile|{source_index}'.encode('utf-8')).hexdigest()[:6]}"


def _shuffled_slots(rng: random.Random) -> list[int]:
    source_indices = list(range(9))
    for _attempt in range(100):
        shuffled = source_indices[:]
        rng.shuffle(shuffled)
        if sum(index != source for index, source in enumerate(shuffled)) >= 8:
            return shuffled
    raise ValueError("could not produce a meaningfully shattered mosaic")


def _phase_offsets(rng: random.Random) -> list[int]:
    for _attempt in range(100):
        phases = [rng.choice(PHASE_TICKS) for _ in range(9)]
        if sum(value != 0 for value in phases) >= 7 and len(set(phases)) >= 5 and 0 in phases:
            return phases
    raise ValueError("could not produce varied temporal offsets")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    digest = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).digest()
    rng = random.Random(int.from_bytes(digest[:8], "big"))
    task_id = str(task.get("id") or "single_scene_split_boxes_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|live-shattered-scene".encode("utf-8")).hexdigest()[:12]
    palette = PALETTES[rng.randrange(len(PALETTES))]
    motif = MOTIFS[rng.randrange(len(MOTIFS))]
    source_by_slot = _shuffled_slots(rng)
    rotation_sources = set(rng.sample(range(9), rng.randint(3, 5)))
    source_phases = _phase_offsets(rng)
    tiles: list[dict[str, Any]] = []
    for slot, source_index in enumerate(source_by_slot):
        tiles.append(
            {
                "id": _tile_id(seed, source_index),
                "source": {"row": source_index // 3, "column": source_index % 3},
                "initial_slot": slot,
                "initial_rotation": 180 if source_index in rotation_sources else 0,
                "initial_phase": source_phases[source_index],
            }
        )
    scene = {
        "width": 900,
        "height": 600,
        "rows": 3,
        "columns": 3,
        "period_ms": 12000,
        "phase_tick_ms": 180,
        "field_seed": rng.randrange(1, 2_000_000_000),
        "horizon": rng.randint(285, 365),
        "target": {
            "radius": rng.randint(24, 34),
            "speed_x_milli": rng.randint(460, 690),
            "speed_y_milli": rng.randint(240, 410),
            "phase": rng.randrange(0, 12000),
        },
        "decoys": [
            {
                "radius": rng.randint(10, 19),
                "speed_x_milli": rng.randint(180, 390),
                "speed_y_milli": rng.randint(110, 260),
                "phase": rng.randrange(0, 12000),
                "depth_milli": rng.choice((350, 520, 740, 900)),
            }
            for _ in range(5)
        ],
        "motif": motif,
    }
    requirements = {
        "hold_ms": 700,
        "sample_ms": 100,
        "minimum_samples": 6,
        "minimum_spatial_touches": len({tile["id"] for tile in tiles if tile["initial_slot"] != (tile["source"]["row"] * 3 + tile["source"]["column"])}),
        "minimum_rotation_touches": len(rotation_sources),
        "minimum_phase_touches": sum(value != 0 for value in source_phases),
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Rebuild the live scene in space, orientation, and time. Hold SYNC while every seam remains continuous.",
        "submit_label": "HOLD SCENE SYNC",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {
            "name": "live_shattered_scene_synchronizer_v1",
            "variant_count": VARIANT_COUNT,
            "variant_count_kind": "palette/motif/permutation/rotation/phase construction space",
        },
        "scene": scene,
        "tiles": tiles,
        "phase_range": {"minimum": -4, "maximum": 4},
        "requirements": requirements,
        "palette": palette,
        "rules": {
            "space": "Drag one tile onto another to swap their mosaic positions.",
            "rotation": "Select a tile and flip it 180 degrees when its fragment is inverted.",
            "time": "Scrub each selected shard onto the master chronograph so motion crosses every seam.",
            "sync": "Hold scene sync continuously for roughly 700 ms after all seams stabilize.",
        },
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "scene": scene,
        "tiles": tiles,
        "phase_range": {"minimum": -4, "maximum": 4},
        "requirements": requirements,
        "solution_slots": {_tile_id(seed, source_index): source_index for source_index in range(9)},
        "solution_rotation": 0,
        "solution_phase": 0,
        "initial_rotation_sources": sorted(rotation_sources),
        "initial_phase_sources": [index for index, value in enumerate(source_phases) if value != 0],
        "palette": palette,
        "motif": motif,
        "variant_count": VARIANT_COUNT,
        "variant_count_kind": "palette/motif/permutation/rotation/phase construction space",
    }
    return public_state, ground_truth
