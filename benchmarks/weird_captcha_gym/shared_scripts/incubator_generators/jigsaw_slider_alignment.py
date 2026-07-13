from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "jigsaw_slider_alignment"
PALETTES = ("oxide_cyan", "signal_violet", "night_orange", "silver_lime")
TRANSFORMS = ("standard", "mirror", "tilt_left", "tilt_right")
NOTCHES = ("round_left", "round_top", "fork_right", "double_notch")
TARGET_DEPTHS = tuple(range(260, 741, 20))
VARIANT_COUNT = len(PALETTES) * len(TRANSFORMS) * len(NOTCHES) * len(TARGET_DEPTHS) * 301 * 2


def _js_round(value: float) -> int:
    return math.floor(value + 0.5)


def _project_offset(depth_milli: int, parallax_milli: int) -> int:
    return _js_round((depth_milli - 500) * parallax_milli / 1000)


def _target_rail(scene: dict[str, Any], target_depth_milli: int) -> int:
    gap = scene["gap"]
    piece = scene["piece"]
    layer = next(item for item in scene["layers"] if item["id"] == gap["layer_id"])
    gap_x = gap["base_x_milli"] + _project_offset(target_depth_milli, layer["parallax_milli"])
    piece_offset = _project_offset(target_depth_milli, piece["parallax_milli"])
    return gap_x - piece_offset


def _scaled_size(base_milli: int, depth_milli: int, scale_base_milli: int, scale_span_milli: int) -> int:
    scale = scale_base_milli + _js_round(scale_span_milli * depth_milli / 1000)
    return _js_round(base_milli * scale / 1000)


def _choose_initial(rng: random.Random, target: int, minimum: int, maximum: int, distance_min: int, distance_max: int) -> int:
    distance = rng.randint(distance_min, distance_max)
    options = [value for value in (target - distance, target + distance) if minimum <= value <= maximum]
    if not options:
        midpoint = (minimum + maximum) // 2
        return minimum if target > midpoint else maximum
    return rng.choice(options)


def _build_scene(rng: random.Random, transform: str, notch: str) -> tuple[dict[str, Any], int, int]:
    sign = -1 if transform == "mirror" else 1
    target_depth = rng.choice(TARGET_DEPTHS)
    layer_parallaxes = [sign * rng.choice((12000, 16000, 20000)), sign * rng.choice((30000, 36000, 42000)), sign * rng.choice((62000, 70000, 78000))]
    layers = [
        {"id": "distant", "parallax_milli": layer_parallaxes[0], "opacity_milli": 720},
        {"id": "middle", "parallax_milli": layer_parallaxes[1], "opacity_milli": 900},
        {"id": "near", "parallax_milli": layer_parallaxes[2], "opacity_milli": 1000},
    ]
    gap_layer = rng.choice(("middle", "near"))
    gap_x_pixels = rng.randint(332, 632)
    if transform == "mirror":
        gap_x_pixels = 820 - gap_x_pixels
    piece_parallax = sign * rng.choice((50000, 56000, 64000))
    piece = {
        "base_y_milli": rng.randint(116000, 138000),
        "base_width_milli": rng.choice((82000, 86000, 90000)),
        "base_height_milli": rng.choice((66000, 70000, 74000)),
        "vertical_span_milli": rng.choice((82000, 90000, 98000)),
        "parallax_milli": piece_parallax,
        "scale_base_milli": 720,
        "scale_span_milli": 480,
    }
    gap = {
        "base_x_milli": gap_x_pixels * 1000,
        "layer_id": gap_layer,
        "notch": notch,
    }
    scene: dict[str, Any] = {
        "width_milli": 820000,
        "height_milli": 390000,
        "layers": layers,
        "gap": gap,
        "piece": piece,
        "rail": {"minimum_milli": 70000, "maximum_milli": 750000},
        "depth": {"minimum_milli": 40, "maximum_milli": 960},
        "decor": {
            "horizon_milli": rng.randint(128000, 172000),
            "orb_x_milli": rng.randint(90000, 710000),
            "orb_y_milli": rng.randint(43000, 95000),
            "spire_x_milli": rng.randint(120000, 700000),
            "bridge_y_milli": rng.randint(258000, 294000),
            "ridge_seed": rng.randrange(1000000),
        },
        "transform": transform,
    }
    target_rail = _target_rail(scene, target_depth)
    rail = scene["rail"]
    if not rail["minimum_milli"] + 30000 <= target_rail <= rail["maximum_milli"] - 30000:
        raise ValueError("generated target rail lies outside practical bounds")
    gap["y_milli"] = piece["base_y_milli"] + _js_round(target_depth * piece["vertical_span_milli"] / 1000)
    gap["width_milli"] = _scaled_size(
        piece["base_width_milli"], target_depth, piece["scale_base_milli"], piece["scale_span_milli"]
    )
    gap["height_milli"] = _scaled_size(
        piece["base_height_milli"], target_depth, piece["scale_base_milli"], piece["scale_span_milli"]
    )
    initial_rail = _choose_initial(rng, target_rail, rail["minimum_milli"], rail["maximum_milli"], 165000, 255000)
    initial_depth = _choose_initial(rng, target_depth, 40, 960, 250, 390)
    if abs(initial_rail - target_rail) < 140000 or abs(initial_depth - target_depth) < 210:
        raise ValueError("generated initial state is not meaningfully displaced")
    scene["rail"]["initial_milli"] = initial_rail
    scene["depth"]["initial_milli"] = initial_depth
    return scene, target_rail, target_depth


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    digest = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).digest()
    rng = random.Random(int.from_bytes(digest[:8], "big"))
    transform = TRANSFORMS[rng.randrange(len(TRANSFORMS))]
    notch = NOTCHES[rng.randrange(len(NOTCHES))]
    for _attempt in range(20):
        try:
            scene, target_rail, target_depth = _build_scene(rng, transform, notch)
            break
        except ValueError:
            continue
    else:
        raise ValueError("could not generate a practical parallax alignment scene")

    task_id = str(task.get("id") or "jigsaw_slider_alignment_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|parallax-jigsaw-alignment".encode("utf-8")).hexdigest()[:12]
    palette = PALETTES[rng.randrange(len(PALETTES))]
    tolerances = {
        "x_milli": 10000,
        "depth_milli": 35,
        "hold_ms": 700,
        "sample_ms": 100,
        "minimum_scan_samples": 6,
        "minimum_rail_travel_milli": 120000,
        "minimum_depth_travel_milli": 180,
        "minimum_inertia_samples": 2,
    }
    inertia = {
        "velocity_threshold_milli_s": 120000,
        "velocity_cap_milli_s": 600000,
        "tick_ms": 50,
        "friction_milli": 780,
        "stop_velocity_milli_s": 15000,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Match the drifting fragment in rail and depth, then hold the optical scan until it locks.",
        "submit_label": "HOLD OPTICAL LOCK",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {
            "name": "parallax_inertial_jigsaw_alignment_v1",
            "variant_count": VARIANT_COUNT,
            "variant_count_kind": "palette/transform/notch/depth/gap/layer construction space",
        },
        "scene": scene,
        "tolerances": tolerances,
        "inertia": inertia,
        "palette": palette,
        "rules": {
            "rail": "Drag the carriage horizontally; a fast release coasts under friction.",
            "depth": "Move the separate depth grip to change scale, height, and layer parallax.",
            "scan": "Hold optical lock continuously while both projected dimensions remain stable.",
        },
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "scene": scene,
        "tolerances": tolerances,
        "inertia": inertia,
        "target_rail_milli": target_rail,
        "target_depth_milli": target_depth,
        "palette": palette,
        "transform": transform,
        "notch": notch,
        "variant_count": VARIANT_COUNT,
        "variant_count_kind": "palette/transform/notch/depth/gap/layer construction space",
    }
    return public_state, ground_truth
