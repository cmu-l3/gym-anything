from __future__ import annotations

import copy
import hashlib
import random
from typing import Any


MECHANIC_ID = "robot_art_critic"
CANVAS_WIDTH = 760
CANVAS_HEIGHT = 470
VARIANT_COUNT = 12_441_600_000
CLASSES = ("umbrella", "sailboat", "fish", "flower", "ladder", "bicycle", "lighthouse", "locomotive")
POSES = {
    "leaning_left": {"angle_deg": -10, "label": "leaning slightly left"},
    "upright": {"angle_deg": 0, "label": "upright"},
    "leaning_right": {"angle_deg": 10, "label": "leaning slightly right"},
}
STYLES = {
    "compact": {"x_scale_milli": 860, "label": "compact"},
    "balanced": {"x_scale_milli": 1000, "label": "balanced"},
    "wide": {"x_scale_milli": 1140, "label": "broad"},
}
EXPECTED_STROKES = {"umbrella": 10, "sailboat": 11, "fish": 10, "flower": 11, "ladder": 11, "bicycle": 11, "lighthouse": 12, "locomotive": 14}
PALETTES = (
    {"name": "gallery_after_dark", "wall": "#d9d4c2", "ink": "#172d38", "robot": "#ff7ce5", "signal": "#56ddc4", "warning": "#ef655c"},
    {"name": "oxide_museum", "wall": "#d9c9b6", "ink": "#3c2c2b", "robot": "#ff9e62", "signal": "#7bc9d4", "warning": "#d94e5b"},
    {"name": "cobalt_salon", "wall": "#cdd5d9", "ink": "#193652", "robot": "#db7bff", "signal": "#73d7a8", "warning": "#e06464"},
    {"name": "lichen_atelier", "wall": "#d2d5bc", "ink": "#293b31", "robot": "#e57ebc", "signal": "#a6d65f", "warning": "#da624e"},
)


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    task_id = str(task.get("id") or "robot_art_critic_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|semantic-studio-v1".encode("utf-8")).hexdigest()[:14]
    target_class = rng.choice(CLASSES)
    pose_name = rng.choice(tuple(POSES))
    style_name = rng.choice(tuple(STYLES))
    palette = copy.deepcopy(rng.choice(PALETTES))
    expected_strokes = EXPECTED_STROKES[target_class]
    stroke_budget = expected_strokes + 1
    requirements = {
        "stroke_budget": stroke_budget,
        "maximum_attempts": 5,
        "minimum_points_per_stroke": 5,
        "minimum_stroke_ms": 42,
        "maximum_sample_gap_px": 46,
        "maximum_sample_interval_ms": 180,
        "minimum_bbox_fraction_milli": 360,
        "maximum_bbox_fraction_milli": 820,
        "maximum_center_offset_milli": 165,
        "acceptance_score_milli": 740,
        "minimum_margin_milli": 90,
    }
    pose = {"name": pose_name, **POSES[pose_name]}
    style = {"name": style_name, **STYLES[style_name]}
    target = {
        "class_name": target_class,
        "display_name": target_class.upper(),
        "pose": pose,
        "style": style,
        "expected_strokes": expected_strokes,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": f"Draw a {style['label']} {target_class} {pose['label']}. Persuade the robot critic using no more than {stroke_budget} continuous strokes.",
        "submit_label": "ASK THE ROBOT CRITIC",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {
            "name": "semantic_polyline_art_studio_v2",
            "variant_count": VARIANT_COUNT,
            "variant_count_kind": "class/pose/style/palette/composition/noise construction space",
        },
        "palette": palette,
        "canvas": {"width": CANVAS_WIDTH, "height": CANVAS_HEIGHT},
        "target": target,
        "class_vocabulary": [item.upper() for item in CLASSES],
        "requirements": requirements,
        "rules": [
            "Draw with continuous pointer holds. Dense paths are recognized; dots and teleporting segments are rejected.",
            "The critic compares raster occupancy, direction, moments, symmetry, endpoints, intersections, turns, and stroke topology across every class.",
            "Undo or clear freely. A valid first drawing may pass; otherwise use coarse critique and try again within the attempt budget.",
            "No solution trace is shown. The named object, pose, and style are the complete brief.",
        ],
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "palette": palette,
        "canvas": public_state["canvas"],
        "target": copy.deepcopy(target),
        "class_vocabulary": list(CLASSES),
        "requirements": requirements,
        "variant_count": VARIANT_COUNT,
        "variant_count_kind": public_state["generator"]["variant_count_kind"],
    }
    assert 10 <= expected_strokes <= stroke_budget <= 15
    return public_state, ground_truth
