#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import random
import secrets
from pathlib import Path
from typing import Any


STATE_DIR = Path(os.environ.get("WEIRD_CAPTCHA_STATE_DIR", "/tmp/weird_captcha_gym"))
INCUBATOR_GENERATOR_ROOT = Path(__file__).resolve().parent / "incubator_generators"


def _load_incubator_generator(mechanic_id: str):
    if not mechanic_id or not mechanic_id.replace("_", "").isalnum():
        return None
    path = INCUBATOR_GENERATOR_ROOT / f"{mechanic_id}.py"
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location(f"weird_captcha_generator_{mechanic_id}", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def has_incubator_generator(mechanic_id: str) -> bool:
    return _load_incubator_generator(str(mechanic_id or "")) is not None


def generate_incubator_candidate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    mechanic_id = str((task.get("metadata") or {}).get("mechanic_id") or "")
    module = _load_incubator_generator(mechanic_id)
    generator = getattr(module, "generate", None) if module is not None else None
    if not callable(generator):
        raise ValueError(f"no incubator generator for {mechanic_id}")
    public_state, ground_truth = generator(task, seed)
    if not isinstance(public_state, dict) or not isinstance(ground_truth, dict):
        raise TypeError(f"incubator generator {mechanic_id} must return two dictionaries")
    if public_state.get("mechanic_id") != mechanic_id or ground_truth.get("mechanic_id") != mechanic_id:
        raise ValueError(f"incubator generator {mechanic_id} returned mismatched mechanic identity")
    return public_state, ground_truth

TARGET_RELATIONS = (
    "branch_left", "branch_right", "branch_fork", "branch_low",
    "branch_high", "hanging_stem", "twig_cluster",
    "split_branch", "arched_branch", "crooked_branch",
    "thin_branch", "shadowed_branch", "near_fork", "upper_twig",
    "lower_twig", "branch_overlap", "center_fork", "side_fork",
)

DECOY_RELATIONS = (
    "ground_left", "ground_right", "pond_reflection", "sign_picture",
    "stump_top", "crate_top", "paper_sticker", "shop_logo",
    "table_top", "basket_near_tree", "poster_overlay", "shadow_blob",
    "fence_overlap", "bucket_side", "ladder_step", "cloud_poster",
    "mushroom_cap", "paint_spot", "mirror_panel", "newspaper_print",
    "window_view", "label_icon", "bench_top", "stone_top",
    "lantern_glow", "kite_mark", "sack_print", "hole_below",
    "jar_label", "near_but_detached", "behind_trunk_gap", "foreground_hand",
    "wheel_center", "flag_dot", "distant_tree", "fruit_slice",
)

APPLE_GRID_VARIANT_COUNT = len(TARGET_RELATIONS) + len(DECOY_RELATIONS)

CURSOR_LENS_SYMBOLS = (
    "double_ring", "notched_diamond", "split_cross", "pinwheel",
    "hourglass", "bracket_star", "offset_square", "hooked_bar",
)
CURSOR_LENS_DECOYS = (
    "blue_ring", "green_cross", "red_square", "gray_spiral",
    "yellow_slash", "black_ticks", "cyan_lozenge", "pink_arc",
    "tiny_grid", "white_chip", "orange_dot", "violet_hook",
)
CURSOR_LENS_VARIANT_COUNT = len(CURSOR_LENS_SYMBOLS) * len(CURSOR_LENS_DECOYS)

TTT_LINES = (
    (0, 1, 2), (3, 4, 5), (6, 7, 8),
    (0, 3, 6), (1, 4, 7), (2, 5, 8),
    (0, 4, 8), (2, 4, 6),
)
BOARD_GAME_OBJECTIVES = ("win_in_one", "block_threat")

MODIFIER_OBJECTS = (
    "key", "lock", "wrench", "anchor", "crown", "hourglass", "bolt", "cup",
)
MODIFIER_STACKS = (
    "rotate", "mirror", "crop", "split", "stripe_occlusion", "fog",
    "invert", "jitter_shadow", "fake_loader", "tile_offset",
)
MODIFIER_GRID_VARIANT_COUNT = len(MODIFIER_OBJECTS) * len(MODIFIER_STACKS) ** 3

SEMANTIC_RELATIONS = (
    ("brass key", "old lock", "opens"),
    ("loose fuse", "dark lamp", "powers"),
    ("red stamp", "blank envelope", "marks"),
    ("ice cube", "warm cup", "cools"),
    ("tiny gear", "stopped clock", "fixes"),
    ("blue thread", "torn kite", "repairs"),
    ("round lens", "empty frame", "completes"),
    ("green plug", "silent radio", "powers"),
    ("paper ticket", "closed gate", "admits"),
    ("wax seal", "folded letter", "seals"),
)
SEMANTIC_VARIANT_COUNT = len(SEMANTIC_RELATIONS) * 24

RELOAD_OVERLAY_TYPES = ("type_code", "press_lit", "repeat_pair")
RELOAD_VARIANT_COUNT = len(RELOAD_OVERLAY_TYPES) ** 2 * 100

ROTATE_CUES = ("label", "icon", "shadow")
ROTATE_VARIANT_COUNT = len(ROTATE_CUES) * 360

FORM_MARK_TYPES = ("sign", "initial", "stamp")
FORM_FIELD_LABELS = (
    "Applicant signature", "Office use only", "Do not sign here",
    "Witness initials", "Machine reviewed", "Date received",
    "Void if signed", "Authorized stamp", "Human declaration",
)
FORM_VARIANT_COUNT = len(FORM_MARK_TYPES) * len(FORM_FIELD_LABELS)

WONKY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
WONKY_VARIANT_COUNT = len(WONKY_ALPHABET) ** 5

TEMPORAL_KINDS = ("ring", "box", "flag", "needle", "chip")
TEMPORAL_VARIANT_COUNT = len(TEMPORAL_KINDS) * 120

GHOST_PATTERN_THEMES = ("orbit", "signal", "totem", "constellation", "hourglass", "crown")
GHOST_JIGSAW_VARIANT_COUNT = len(GHOST_PATTERN_THEMES) * 9 * 40320

CONSTELLATION_SHAPES = ("heart", "star", "spiral", "fish", "umbrella", "key")
CONSTELLATION_VARIANT_COUNT = len(CONSTELLATION_SHAPES) * 6400

GRILL_FOODS = ("steak", "egg", "chicken", "potato", "sausage", "naan")
GRILL_VARIANT_COUNT = math.factorial(len(GRILL_FOODS)) * 120

ROTATING_KEYBOARD_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
ROTATING_KEYBOARD_VARIANT_COUNT = len(ROTATING_KEYBOARD_ALPHABET) ** 5

SLOT_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
SLOT_SYMBOLS = ("◆", "●", "✦", "♢", "▰", "✶")
SLOT_REEL_VARIANT_COUNT = len(SLOT_ALPHABET) ** 5 * 24

DOMINO_COLORS = ("vermilion", "saffron", "cobalt")
DOMINO_VARIANT_COUNT = 720 * 9

CONSEQUENCE_SCENES = (
    ("moth", "release", "jar"),
    ("pilgrim", "share", "hoard"),
    ("fox", "free", "trap"),
    ("seedling", "water", "salt"),
)
CONSEQUENCES_VARIANT_COUNT = 24 * 16

POPUP_THEMES = ("miracle", "warning", "coupon", "romance", "system", "horoscope", "winner", "download")
POPUP_VARIANT_COUNT = 40320 * 8

FUNERAL_FLOWER_KINDS = ("poppy", "daisy", "iris", "lavender")
FUNERAL_VARIANT_COUNT = 4096

SLIME_LANE_TYPES = ("road", "water", "rail")
SLIME_VARIANT_COUNT = 9 ** 8 * 6


def load_task(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def challenge_seed(task: dict[str, Any], explicit_seed: str | None) -> str:
    if explicit_seed:
        return explicit_seed
    return secrets.token_hex(16)


def seed_int(seed: str, salt: str) -> int:
    raw = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(raw[:16], 16)


def pick(rng: random.Random, values: tuple[str, ...]) -> str:
    return values[rng.randrange(len(values))]


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def point_on_branch(branch: dict[str, float], t: float, jitter: float, rng: random.Random) -> tuple[float, float]:
    x1 = branch["x1"]
    y1 = branch["y1"]
    x2 = branch["x2"]
    y2 = branch["y2"]
    cx = branch["cx"]
    cy = branch["cy"]
    omt = 1.0 - t
    x = omt * omt * x1 + 2 * omt * t * cx + t * t * x2
    y = omt * omt * y1 + 2 * omt * t * cy + t * t * y2
    return x + rng.uniform(-jitter, jitter), y + rng.uniform(-jitter, jitter)


def make_tree(rng: random.Random) -> dict[str, Any]:
    base_x = rng.uniform(88, 132)
    base_y = rng.uniform(132, 146)
    top_y = rng.uniform(48, 68)
    lean = rng.uniform(-22, 22)
    trunk = {
        "base_x": round(base_x, 2),
        "base_y": round(base_y, 2),
        "top_x": round(base_x + lean, 2),
        "top_y": round(top_y, 2),
        "width": round(rng.uniform(12, 19), 2),
        "bend": round(rng.uniform(-18, 18), 2),
    }
    branches: list[dict[str, float]] = []
    branch_count = rng.randint(3, 5)
    for idx in range(branch_count):
        side = -1 if idx % 2 == 0 else 1
        if rng.random() < 0.35:
            side *= -1
        y1 = rng.uniform(54, 92)
        x1 = base_x + lean * ((base_y - y1) / max(1, base_y - top_y)) + rng.uniform(-5, 5)
        length = rng.uniform(46, 78)
        y2 = y1 + rng.uniform(-28, 13)
        x2 = x1 + side * length
        branches.append({
            "x1": round(x1, 2),
            "y1": round(y1, 2),
            "cx": round((x1 + x2) / 2 + side * rng.uniform(4, 18), 2),
            "cy": round(min(y1, y2) - rng.uniform(12, 24), 2),
            "x2": round(clamp(x2, 24, 196), 2),
            "y2": round(clamp(y2, 20, 124), 2),
            "width": round(rng.uniform(5.0, 9.5), 2),
        })
    crown = {
        "x": round(trunk["top_x"] + rng.uniform(-6, 8), 2),
        "y": round(top_y + rng.uniform(-10, 10), 2),
        "rx": round(rng.uniform(44, 68), 2),
        "ry": round(rng.uniform(16, 26), 2),
        "lobes": rng.randint(3, 5),
    }
    return {"trunk": trunk, "branches": branches, "crown": crown}


def apple_at(x: float, y: float, rng: random.Random, *, opacity: float = 1.0, scale: float | None = None) -> dict[str, Any]:
    return {
        "x": round(clamp(x, 18, 202), 2),
        "y": round(clamp(y, 18, 136), 2),
        "r": round(scale if scale is not None else rng.uniform(9.0, 14.5), 2),
        "tilt": round(rng.uniform(-0.65, 0.65), 3),
        "hue": rng.randrange(4),
        "opacity": round(opacity, 2),
    }


def prop(kind: str, rng: random.Random, **kwargs: Any) -> dict[str, Any]:
    data = {"kind": kind, "j": round(rng.random(), 4)}
    data.update({key: round(value, 2) if isinstance(value, float) else value for key, value in kwargs.items()})
    return data


def separated_ground_point(trunk: dict[str, float], rng: random.Random, *, side: int | None = None) -> tuple[float, float]:
    direction = side if side in {-1, 1} else rng.choice((-1, 1))
    x = clamp(trunk["base_x"] + direction * rng.uniform(64, 90), 24, 196)
    y = rng.uniform(112, 135)
    return x, y


def attached_apple(anchor_x: float, anchor_y: float, rng: random.Random, props: list[dict[str, Any]]) -> dict[str, Any]:
    apple = apple_at(
        anchor_x + rng.uniform(-1.5, 1.5),
        anchor_y + rng.uniform(9.0, 13.0),
        rng,
        scale=rng.uniform(11.0, 14.0),
    )
    props.append(prop(
        "stem_line",
        rng,
        x=apple["x"],
        y1=anchor_y - 4.0,
        y2=apple["y"] - apple["r"] * 0.55,
    ))
    return apple


def place_target(relation: str, tree: dict[str, Any], rng: random.Random) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    branches = tree["branches"]
    crown = tree["crown"]
    branch = branches[rng.randrange(len(branches))]
    props: list[dict[str, Any]] = []

    if relation.startswith("branch") or relation in {
        "twig_cluster", "split_branch", "arched_branch", "crooked_branch",
        "thin_branch", "shadowed_branch", "near_fork", "upper_twig",
        "lower_twig", "branch_overlap", "branch_end_small", "branch_end_large",
        "center_fork", "side_fork",
    }:
        t = {
            "branch_left": 0.34, "branch_right": 0.66,
            "branch_fork": 0.48, "branch_low": 0.35, "branch_high": 0.66,
        }.get(relation, rng.uniform(0.25, 0.82))
        x, y = point_on_branch(branch, t, 2.0, rng)
        if relation in {"branch_overlap", "shadowed_branch"}:
            props.append(prop("foreground_leaf", rng, x=x + rng.uniform(-10, 10), y=y - rng.uniform(8, 16)))
        return attached_apple(x, y, rng, props), props

    x, y = point_on_branch(branch, rng.uniform(0.3, 0.75), 5, rng)
    return attached_apple(x, y, rng, props), props


def place_decoy(relation: str, tree: dict[str, Any], rng: random.Random) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    trunk = tree["trunk"]
    props: list[dict[str, Any]] = []

    if relation in {"ground_left", "ground_right", "near_but_detached"}:
        side = -1 if relation == "ground_left" else 1
        x, y = separated_ground_point(trunk, rng, side=side)
        props.append(prop("ground_shadow", rng, x=x, y=y + 8))
        return apple_at(x, y, rng), props
    if relation == "pond_reflection":
        x, y = separated_ground_point(trunk, rng)
        props.append(prop("pond", rng, x=x, y=y))
        return apple_at(x, y + 3, rng, opacity=0.48), props
    if relation in {
        "sign_picture", "poster_overlay", "label_icon", "window_view",
        "paper_sticker", "shop_logo", "cloud_poster", "paint_spot",
        "flag_dot", "jar_label", "newspaper_print",
    }:
        x, y = separated_ground_point(trunk, rng)
        y = clamp(y - rng.uniform(28, 46), 58, 102)
        props.append(prop("sign", rng, x=x, y=y, w=rng.uniform(48, 72), h=rng.uniform(30, 48)))
        return apple_at(x, y, rng, scale=rng.uniform(6.5, 10.0)), props
    if relation in {"stump_top", "crate_top", "basket_near_tree", "bench_top", "stone_top", "table_top", "bucket_side"}:
        x, y = separated_ground_point(trunk, rng)
        y = clamp(y - rng.uniform(2, 16), 92, 124)
        props.append(prop(relation, rng, x=x, y=y))
        return apple_at(x, y - rng.uniform(12, 22), rng), props
    if relation in {"fence_overlap", "ladder_step", "behind_trunk_gap", "foreground_hand"}:
        x, y = separated_ground_point(trunk, rng)
        y = clamp(y - rng.uniform(6, 26), 82, 128)
        props.append(prop(relation, rng, x=x, y=y))
        return apple_at(x + rng.uniform(-18, 24), y + rng.uniform(-16, 14), rng), props
    if relation in {"mirror_panel", "hole_below"}:
        x, y = separated_ground_point(trunk, rng)
        props.append(prop(relation, rng, x=x, y=y))
        return apple_at(x, y, rng, opacity=0.62), props
    if relation == "fruit_slice":
        x, y = separated_ground_point(trunk, rng)
        props.append(prop("plate", rng, x=x, y=y + 8))
        return apple_at(x, y, rng, scale=rng.uniform(7.5, 10.0)), props
    if relation in {"mushroom_cap", "lantern_glow", "kite_mark", "sack_print", "wheel_center"}:
        x, y = separated_ground_point(trunk, rng)
        y = clamp(y - rng.uniform(8, 34), 78, 128)
        props.append(prop(relation, rng, x=x, y=y))
        return apple_at(x, y, rng, scale=rng.uniform(7.0, 11.0)), props
    if relation == "distant_tree":
        props.append(prop("distant_tree", rng, x=rng.uniform(32, 188), y=rng.uniform(40, 78)))
        x, y = separated_ground_point(trunk, rng)
        props.append(prop("ground_shadow", rng, x=x, y=y + 8))
        return apple_at(x, y, rng, scale=rng.uniform(6.5, 9.0)), props

    x, y = separated_ground_point(trunk, rng)
    return apple_at(x, y, rng), props


def make_tile(task_seed: str, index: int, relation: str, target: bool) -> tuple[dict[str, Any], str | None]:
    rng = random.Random(seed_int(task_seed, f"tile:{index}:{relation}"))
    tile_id = f"tile-{index + 1}-{hashlib.sha256(f'{task_seed}|{index}'.encode('utf-8')).hexdigest()[:8]}"
    tree = make_tree(rng)
    apple, props = place_target(relation, tree, rng) if target else place_decoy(relation, tree, rng)
    occluders = []
    scratch_count = rng.randint(0, 1) if target else rng.randint(1, 4)
    for _ in range(scratch_count):
        occluders.append(prop("scratch", rng, x=rng.uniform(8, 212), y=rng.uniform(12, 142), w=rng.uniform(18, 70)))
    if (not target) and rng.random() < 0.45:
        occluders.append(prop("fog_band", rng, x=rng.uniform(16, 186), y=rng.uniform(40, 132), w=rng.uniform(40, 120)))
    tile = {
        "id": tile_id,
        "frame": {
            "palette": rng.randrange(9),
            "tilt": round(rng.uniform(-4.5, 4.5), 2),
            "grain": round(rng.uniform(0.1, 0.36), 3),
            "crop": round(rng.uniform(0.98, 1.08), 3),
        },
        "tree": tree,
        "apples": [apple],
        "props": props,
        "occluders": occluders,
    }
    return tile, tile_id if target else None


def generate_surreal_apple_on_tree_grid(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("surreal_apple_on_tree_grid"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "apple-grid"))
    target_count = rng.randint(3, 4)
    target_relations = rng.sample(TARGET_RELATIONS, target_count)
    decoy_relations = rng.sample(DECOY_RELATIONS, 9 - target_count)
    specs = [(relation, True) for relation in target_relations] + [(relation, False) for relation in decoy_relations]
    rng.shuffle(specs)

    tiles: list[dict[str, Any]] = []
    expected_ids: list[str] = []
    audit_tiles: list[dict[str, Any]] = []
    for index, (relation, target) in enumerate(specs):
        tile, expected_id = make_tile(seed, index, relation, target)
        tiles.append(tile)
        audit_tiles.append({"tile_id": tile["id"], "relation": relation, "target": target})
        if expected_id:
            expected_ids.append(expected_id)

    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "surreal_apple_on_tree_grid",
        "task_id": task["id"],
        "prompt": task.get("natural_language") or task.get("description") or "Select every image where the apple is visibly attached to the tree.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/apple_grid_procedural_v0.json",
        "generator": {
            "name": "apple_grid_procedural_v1",
            "variant_count": APPLE_GRID_VARIANT_COUNT,
        },
        "tiles": tiles,
    }
    ground_truth = {
        "mechanic_id": "surreal_apple_on_tree_grid",
        "task_id": task["id"],
        "seed": seed,
        "expected_tile_ids": expected_ids,
        "audit_tiles": audit_tiles,
        "variant_count": APPLE_GRID_VARIANT_COUNT,
    }
    return public_state, ground_truth


def separated_from_existing(
    rng: random.Random,
    width: float,
    height: float,
    existing: list[tuple[float, float]],
    *,
    margin: float,
    min_distance: float,
) -> tuple[float, float]:
    for _ in range(240):
        x = rng.uniform(margin, width - margin)
        y = rng.uniform(margin, height - margin)
        if all((x - px) ** 2 + (y - py) ** 2 >= min_distance ** 2 for px, py in existing):
            return x, y
    return rng.uniform(margin, width - margin), rng.uniform(margin, height - margin)


def generate_cursor_lens_reveal(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("cursor_lens_reveal"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "cursor-lens"))
    width = 660
    height = 390
    lens_radius = rng.randint(52, 64)
    target_radius = rng.randint(15, 18)
    target_x, target_y = separated_from_existing(rng, width, height, [], margin=58, min_distance=90)
    symbol = pick(rng, CURSOR_LENS_SYMBOLS)
    target_id = f"lens-target-{hashlib.sha256(f'{seed}|target'.encode('utf-8')).hexdigest()[:8]}"

    occupied = [(target_x, target_y)]
    hidden_marks: list[dict[str, Any]] = [{
        "id": target_id,
        "kind": "target",
        "symbol": symbol,
        "x": round(target_x, 2),
        "y": round(target_y, 2),
        "r": target_radius,
        "rot": round(rng.uniform(-0.9, 0.9), 3),
        "scale": round(rng.uniform(0.92, 1.1), 3),
    }]
    decoy_count = rng.randint(9, 14)
    for idx in range(decoy_count):
        x, y = separated_from_existing(rng, width, height, occupied, margin=34, min_distance=52)
        occupied.append((x, y))
        hidden_marks.append({
            "id": f"lens-decoy-{idx}-{hashlib.sha256(f'{seed}|decoy|{idx}'.encode('utf-8')).hexdigest()[:5]}",
            "kind": "decoy",
            "symbol": pick(rng, CURSOR_LENS_DECOYS),
            "x": round(x, 2),
            "y": round(y, 2),
            "r": rng.randint(8, 17),
            "rot": round(rng.uniform(-1.8, 1.8), 3),
            "scale": round(rng.uniform(0.75, 1.25), 3),
            "alpha": round(rng.uniform(0.45, 0.78), 2),
        })

    clutter: list[dict[str, Any]] = []
    for idx in range(90):
        clutter.append({
            "kind": "scratch" if idx % 5 else "dash",
            "x": round(rng.uniform(0, width), 2),
            "y": round(rng.uniform(0, height), 2),
            "w": round(rng.uniform(10, 54), 2),
            "rot": round(rng.uniform(-1.7, 1.7), 3),
            "alpha": round(rng.uniform(0.08, 0.24), 3),
        })
    for idx in range(28):
        clutter.append({
            "kind": "cell",
            "x": round(rng.uniform(14, width - 14), 2),
            "y": round(rng.uniform(14, height - 14), 2),
            "r": round(rng.uniform(4, 14), 2),
            "alpha": round(rng.uniform(0.05, 0.16), 3),
        })

    challenge_id = hashlib.sha256(f"{seed}|cursor-lens".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "cursor_lens_reveal",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": (
            task.get("natural_language")
            or task.get("description")
            or "Use the cursor lens to find the amber target mark and click its center."
        ),
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/cursor_lens_procedural_v0.json",
        "generator": {
            "name": "cursor_lens_procedural_v1",
            "variant_count": CURSOR_LENS_VARIANT_COUNT,
        },
        "surface": {
            "width": width,
            "height": height,
            "lens_radius": lens_radius,
            "theme": rng.randrange(7),
            "grain": round(rng.uniform(0.18, 0.36), 3),
        },
        "hidden_marks": hidden_marks,
        "clutter": clutter,
    }
    ground_truth = {
        "mechanic_id": "cursor_lens_reveal",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "target_id": target_id,
        "target_symbol": symbol,
        "expected_click": {
            "x": round(target_x, 2),
            "y": round(target_y, 2),
            "radius": target_radius,
        },
        "variant_count": CURSOR_LENS_VARIANT_COUNT,
    }
    return public_state, ground_truth


def ttt_winner(board: tuple[str, ...], mark: str) -> bool:
    return any(all(board[index] == mark for index in line) for line in TTT_LINES)


def ttt_immediate_moves(board: tuple[str, ...], mark: str) -> list[int]:
    moves: list[int] = []
    for index, value in enumerate(board):
        if value:
            continue
        candidate = list(board)
        candidate[index] = mark
        if ttt_winner(tuple(candidate), mark):
            moves.append(index)
    return moves


def ttt_candidates(objective: str) -> list[tuple[tuple[str, ...], int]]:
    values = ("", "X", "O")
    candidates: list[tuple[tuple[str, ...], int]] = []
    for raw in range(3 ** 9):
        n = raw
        board: list[str] = []
        for _ in range(9):
            board.append(values[n % 3])
            n //= 3
        board_tuple = tuple(board)
        x_count = board_tuple.count("X")
        o_count = board_tuple.count("O")
        empty_count = board_tuple.count("")
        if x_count != o_count or empty_count < 2 or empty_count > 5:
            continue
        if ttt_winner(board_tuple, "X") or ttt_winner(board_tuple, "O"):
            continue
        x_wins = ttt_immediate_moves(board_tuple, "X")
        o_wins = ttt_immediate_moves(board_tuple, "O")
        if objective == "win_in_one" and len(x_wins) == 1:
            candidates.append((board_tuple, x_wins[0]))
        elif objective == "block_threat" and not x_wins and len(o_wins) == 1:
            candidates.append((board_tuple, o_wins[0]))
    return candidates


def generate_board_game_captcha(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("board_game_captcha"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "board-game"))
    objective = pick(rng, BOARD_GAME_OBJECTIVES)
    candidates = ttt_candidates(objective)
    if not candidates:
        raise RuntimeError(f"no tic-tac-toe candidates for {objective}")
    board, solution_index = candidates[rng.randrange(len(candidates))]
    challenge_id = hashlib.sha256(f"{seed}|board-game".encode("utf-8")).hexdigest()[:12]
    prompt = (
        "Play X to win this board."
        if objective == "win_in_one"
        else "Play X to block O's immediate win."
    )
    cells = []
    for index, value in enumerate(board):
        row = index // 3
        col = index % 3
        cells.append({
            "id": f"cell-{row}-{col}",
            "row": row,
            "col": col,
            "value": value,
        })
    solution_row = solution_index // 3
    solution_col = solution_index % 3
    solved_board = list(board)
    solved_board[solution_index] = "X"

    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "board_game_captcha",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": prompt,
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/board_game_ttt_procedural_v0.json",
        "generator": {
            "name": "board_game_ttt_procedural_v1",
            "variant_count": len(candidates),
        },
        "game": {
            "type": "tic_tac_toe",
            "player": "X",
            "opponent": "O",
            "objective": objective,
            "theme": rng.randrange(6),
            "cells": cells,
        },
    }
    ground_truth = {
        "mechanic_id": "board_game_captcha",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "game_type": "tic_tac_toe",
        "objective": objective,
        "board": list(board),
        "solution_cell_id": f"cell-{solution_row}-{solution_col}",
        "solution": {
            "index": solution_index,
            "row": solution_row,
            "col": solution_col,
            "player": "X",
        },
        "solved_board": solved_board,
        "validation": {
            "x_immediate_wins": ttt_immediate_moves(board, "X"),
            "o_immediate_wins": ttt_immediate_moves(board, "O"),
            "unique_solution": True,
        },
        "variant_count": len(candidates),
    }
    return public_state, ground_truth


def modifier_stack_for_tile(rng: random.Random, *, target: bool) -> list[dict[str, Any]]:
    count = rng.randint(3, 5 if target else 6)
    names = rng.sample(MODIFIER_STACKS, count)
    stack: list[dict[str, Any]] = []
    for name in names:
        if name == "rotate":
            stack.append({"name": name, "angle": round(rng.uniform(-0.72, 0.72), 3)})
        elif name == "crop":
            stack.append({
                "name": name,
                "x": round(rng.uniform(-16, 16), 2),
                "y": round(rng.uniform(-12, 12), 2),
                "scale": round(rng.uniform(0.82, 1.08), 3),
            })
        elif name == "split":
            stack.append({"name": name, "offset": round(rng.uniform(6, 18), 2), "axis": rng.choice(("x", "y"))})
        elif name == "stripe_occlusion":
            stack.append({"name": name, "angle": round(rng.uniform(-0.55, 0.55), 3), "count": rng.randint(2, 4)})
        elif name == "fog":
            stack.append({"name": name, "x": round(rng.uniform(28, 112), 2), "y": round(rng.uniform(26, 82), 2)})
        elif name == "jitter_shadow":
            stack.append({"name": name, "dx": round(rng.uniform(-9, 9), 2), "dy": round(rng.uniform(-8, 8), 2)})
        elif name == "fake_loader":
            stack.append({"name": name, "progress": round(rng.uniform(0.28, 0.82), 2)})
        elif name == "tile_offset":
            stack.append({"name": name, "dx": round(rng.uniform(-10, 10), 2), "dy": round(rng.uniform(-8, 8), 2)})
        else:
            stack.append({"name": name})
    return stack


def generate_modifier_stack_image_grid(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("modifier_stack_image_grid"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "modifier-stack"))
    target_kind = pick(rng, MODIFIER_OBJECTS)
    target_count = rng.randint(4, 6)
    cells_total = 16
    decoy_kinds = [kind for kind in MODIFIER_OBJECTS if kind != target_kind]
    specs: list[tuple[str, bool]] = [(target_kind, True) for _ in range(target_count)]
    for _ in range(cells_total - target_count):
        specs.append((rng.choice(decoy_kinds), False))
    rng.shuffle(specs)

    tiles: list[dict[str, Any]] = []
    expected_ids: list[str] = []
    audit_tiles: list[dict[str, Any]] = []
    for index, (kind, target) in enumerate(specs):
        tile_id = f"mod-{index + 1}-{hashlib.sha256(f'{seed}|mod|{index}'.encode('utf-8')).hexdigest()[:8]}"
        tile_rng = random.Random(seed_int(seed, f"modifier-tile:{index}:{kind}"))
        stack = modifier_stack_for_tile(tile_rng, target=target)
        tile = {
            "id": tile_id,
            "kind": kind,
            "frame": {
                "theme": tile_rng.randrange(8),
                "tilt": round(tile_rng.uniform(-2.5, 2.5), 2),
                "grain": round(tile_rng.uniform(0.18, 0.42), 3),
            },
            "object": {
                "x": round(tile_rng.uniform(65, 95), 2),
                "y": round(tile_rng.uniform(48, 72), 2),
                "scale": round(tile_rng.uniform(0.78, 1.08), 3),
                "color": tile_rng.randrange(8),
            },
            "modifiers": stack,
            "noise": [
                {
                    "x": round(tile_rng.uniform(4, 156), 2),
                    "y": round(tile_rng.uniform(4, 116), 2),
                    "w": round(tile_rng.uniform(10, 42), 2),
                    "a": round(tile_rng.uniform(-1.2, 1.2), 3),
                }
                for _ in range(tile_rng.randint(7, 14))
            ],
        }
        tiles.append(tile)
        audit_tiles.append({"tile_id": tile_id, "kind": kind, "target": target, "modifiers": [item["name"] for item in stack]})
        if target:
            expected_ids.append(tile_id)

    challenge_id = hashlib.sha256(f"{seed}|modifier-stack".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "modifier_stack_image_grid",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": f"Select every corrupted {target_kind}.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/modifier_stack_procedural_v0.json",
        "generator": {
            "name": "modifier_stack_procedural_v1",
            "variant_count": MODIFIER_GRID_VARIANT_COUNT,
        },
        "grid": {
            "columns": 4,
            "rows": 4,
            "target_kind": target_kind,
        },
        "tiles": tiles,
    }
    ground_truth = {
        "mechanic_id": "modifier_stack_image_grid",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "target_kind": target_kind,
        "expected_tile_ids": expected_ids,
        "audit_tiles": audit_tiles,
        "variant_count": MODIFIER_GRID_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_semantic_drag_drop_absurdity(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("semantic_drag_drop_absurdity"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "semantic-drag"))
    chosen = rng.sample(SEMANTIC_RELATIONS, 4)
    objects: list[dict[str, Any]] = []
    zones: list[dict[str, Any]] = []
    assignments: dict[str, str] = {}
    for index, (object_label, target_label, relation) in enumerate(chosen):
        object_id = f"obj-{index}-{hashlib.sha256(f'{seed}|obj|{index}'.encode('utf-8')).hexdigest()[:6]}"
        zone_id = f"zone-{index}-{hashlib.sha256(f'{seed}|zone|{index}'.encode('utf-8')).hexdigest()[:6]}"
        objects.append({
            "id": object_id,
            "label": object_label,
            "kind": object_label.split()[-1],
            "color": rng.randrange(8),
            "x": round(34 + (index % 2) * 132 + rng.uniform(-8, 8), 2),
            "y": round(52 + (index // 2) * 116 + rng.uniform(-8, 8), 2),
        })
        zones.append({
            "id": zone_id,
            "label": target_label,
            "relation": relation,
            "x": round(390 + (index % 2) * 132 + rng.uniform(-8, 8), 2),
            "y": round(50 + (index // 2) * 116 + rng.uniform(-8, 8), 2),
        })
        assignments[object_id] = zone_id
    rng.shuffle(objects)
    rng.shuffle(zones)
    challenge_id = hashlib.sha256(f"{seed}|semantic-drag".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "semantic_drag_drop_absurdity",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Drag each object where it belongs.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/source_grounded_mechanics_v0.json",
        "generator": {"name": "semantic_drag_drop_procedural_v1", "variant_count": SEMANTIC_VARIANT_COUNT},
        "surface": {"width": 690, "height": 330, "theme": rng.randrange(6)},
        "objects": objects,
        "zones": zones,
    }
    ground_truth = {
        "mechanic_id": "semantic_drag_drop_absurdity",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "expected_assignments": assignments,
        "relation_graph": [
            {"object": obj, "zone": zone, "relation": relation}
            for (obj, zone, relation) in chosen
        ],
        "variant_count": SEMANTIC_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_reload_interruption(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("reload_interruption"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "reload-interruption"))
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    interruptions: list[dict[str, Any]] = []
    for index, step in enumerate((2, 4)):
        overlay_type = rng.choice(RELOAD_OVERLAY_TYPES)
        overlay_id = f"interrupt-{index}-{hashlib.sha256(f'{seed}|interrupt|{index}'.encode('utf-8')).hexdigest()[:6]}"
        if overlay_type == "type_code":
            code = "".join(rng.choice(alphabet) for _ in range(4))
            interruptions.append({
                "id": overlay_id,
                "type": overlay_type,
                "step": step,
                "prompt": "Enter the reload token.",
                "code": code,
                "answer": code,
            })
        elif overlay_type == "press_lit":
            buttons = rng.sample(("AMBER", "CYAN", "LIME", "ROSE"), 4)
            answer = rng.choice(buttons)
            interruptions.append({
                "id": overlay_id,
                "type": overlay_type,
                "step": step,
                "prompt": f"Press {answer}.",
                "buttons": buttons,
                "answer": answer,
            })
        else:
            pair = [rng.choice(("UP", "DOWN", "LEFT", "RIGHT")), rng.choice(("UP", "DOWN", "LEFT", "RIGHT"))]
            interruptions.append({
                "id": overlay_id,
                "type": overlay_type,
                "step": step,
                "prompt": "Repeat the two-symbol sequence.",
                "sequence": pair,
                "buttons": ["UP", "DOWN", "LEFT", "RIGHT"],
                "answer": pair,
            })
    challenge_id = hashlib.sha256(f"{seed}|reload-interruption".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "reload_interruption",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Finish the base task. Clear any verification interruptions.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/source_grounded_mechanics_v0.json",
        "generator": {"name": "reload_interruption_procedural_v1", "variant_count": RELOAD_VARIANT_COUNT},
        "base_task": {
            "steps_required": 6,
            "label": rng.choice(("RELOAD", "RECHARGE", "RESTORE")),
            "theme": rng.randrange(6),
        },
        "interruptions": interruptions,
    }
    ground_truth = {
        "mechanic_id": "reload_interruption",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "steps_required": 6,
        "expected_interruptions": [item["id"] for item in interruptions],
        "answers": {item["id"]: item["answer"] for item in interruptions},
        "variant_count": RELOAD_VARIANT_COUNT,
    }
    return public_state, ground_truth


def normalize_angle(angle: float) -> float:
    return angle % 360.0


def circular_delta(a: float, b: float) -> float:
    return abs((a - b + 180.0) % 360.0 - 180.0)


def generate_rotate_wrong_thing_upright(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("rotate_wrong_thing_upright"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "rotate-wrong-thing"))
    target_cue = rng.choice(ROTATE_CUES)
    offsets = {
        "label": rng.choice((45, 90, 135, 180, 225, 270, 315)),
        "icon": rng.choice((30, 60, 120, 210, 300)),
        "shadow": rng.choice((20, 70, 160, 250, 330)),
    }
    initial_angle = rng.randrange(0, 360, 15)
    target_angle = normalize_angle(-offsets[target_cue])
    prompt_by_cue = {
        "label": "Rotate the label upright.",
        "icon": "Make the small icon point upward.",
        "shadow": "Turn the shadow upright.",
    }
    challenge_id = hashlib.sha256(f"{seed}|rotate".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "rotate_wrong_thing_upright",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": prompt_by_cue[target_cue],
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/source_grounded_mechanics_v0.json",
        "generator": {"name": "rotate_conflicting_cues_v1", "variant_count": ROTATE_VARIANT_COUNT},
        "rotation": {
            "initial_angle": initial_angle,
            "step": 15,
            "target_cue": target_cue,
            "cue_offsets": offsets,
            "theme": rng.randrange(6),
            "tolerance": 10,
        },
    }
    ground_truth = {
        "mechanic_id": "rotate_wrong_thing_upright",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "target_cue": target_cue,
        "target_angle": target_angle,
        "tolerance": 10,
        "initial_angle": initial_angle,
        "cue_offsets": offsets,
        "variant_count": ROTATE_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_bureaucratic_signature_trap(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("bureaucratic_signature_trap"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "bureaucratic-form"))
    labels = list(rng.sample(FORM_FIELD_LABELS, 6))
    required_label = rng.choice(labels)
    required_mark = rng.choice(FORM_MARK_TYPES)
    fields: list[dict[str, Any]] = []
    for index, label in enumerate(labels):
        field_id = f"field-{index}-{hashlib.sha256(f'{seed}|field|{index}'.encode('utf-8')).hexdigest()[:6]}"
        fields.append({
            "id": field_id,
            "label": label,
            "x": 32 + (index % 2) * 292,
            "y": 66 + (index // 2) * 74,
            "w": 250,
            "h": 48,
        })
    required_field = next(field for field in fields if field["label"] == required_label)
    verb = {"sign": "Sign", "initial": "Initial", "stamp": "Stamp"}[required_mark]
    prompt = f"{verb} the field labeled \"{required_label}\"."
    challenge_id = hashlib.sha256(f"{seed}|form".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "bureaucratic_signature_trap",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": prompt,
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/source_grounded_mechanics_v0.json",
        "generator": {"name": "bureaucratic_form_procedural_v1", "variant_count": FORM_VARIANT_COUNT},
        "form": {
            "title": rng.choice(("Verification Form 12-B", "Human Exception Waiver", "Counter-Signature Slip")),
            "fields": fields,
            "tools": list(FORM_MARK_TYPES),
            "theme": rng.randrange(6),
        },
    }
    ground_truth = {
        "mechanic_id": "bureaucratic_signature_trap",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "required_marks": [{
            "field_id": required_field["id"],
            "field_label": required_label,
            "mark_type": required_mark,
        }],
        "variant_count": FORM_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_wonky_text_hostile_rendering(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("wonky_text_hostile_rendering"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "wonky-text"))
    token = "".join(rng.choice(WONKY_ALPHABET) for _ in range(rng.randint(5, 6)))
    decoys = []
    for index in range(5):
        chars = list(token)
        pos = rng.randrange(len(chars))
        chars[pos] = rng.choice(WONKY_ALPHABET.replace(chars[pos], ""))
        decoys.append("".join(chars))
    challenge_id = hashlib.sha256(f"{seed}|wonky".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "wonky_text_hostile_rendering",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Enter the warped text.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/source_grounded_mechanics_v0.json",
        "generator": {"name": "wonky_text_procedural_v1", "variant_count": WONKY_VARIANT_COUNT},
        "text_challenge": {
            "token": token,
            "decoys": decoys,
            "theme": rng.randrange(6),
            "noise": [
                {
                    "x": round(rng.uniform(8, 610), 2),
                    "y": round(rng.uniform(10, 170), 2),
                    "w": round(rng.uniform(30, 130), 2),
                    "angle": round(rng.uniform(-0.8, 0.8), 3),
                }
                for _ in range(28)
            ],
            "char_offsets": [
                {
                    "dx": round(rng.uniform(-4, 4), 2),
                    "dy": round(rng.uniform(-11, 11), 2),
                    "angle": round(rng.uniform(-0.45, 0.45), 3),
                    "split": rng.choice((True, False)),
                }
                for _ in token
            ],
        },
    }
    ground_truth = {
        "mechanic_id": "wonky_text_hostile_rendering",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "token": token,
        "accepted": [token],
        "decoys": decoys,
        "variant_count": WONKY_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_temporal_memory_first_change(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("temporal_memory_first_change"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "temporal-first-change"))
    object_count = 5
    target_index = rng.randrange(object_count)
    first_change_ms = rng.randrange(1400, 2600, 200)
    objects = []
    for index in range(object_count):
        object_id = f"temporal-{index}-{hashlib.sha256(f'{seed}|temporal|{index}'.encode('utf-8')).hexdigest()[:6]}"
        objects.append({
            "id": object_id,
            "kind": TEMPORAL_KINDS[index % len(TEMPORAL_KINDS)],
            "x": round(80 + index * 118 + rng.uniform(-16, 16), 2),
            "y": round(rng.uniform(92, 205), 2),
            "vx": round(rng.uniform(-12, 12), 2),
            "vy": round(rng.uniform(-8, 8), 2),
            "color": rng.randrange(6),
            "change_ms": first_change_ms if index == target_index else first_change_ms + rng.randrange(700, 1800, 200),
        })
    target = objects[target_index]
    challenge_id = hashlib.sha256(f"{seed}|temporal".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "temporal_memory_first_change",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Click the first object that changed.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/source_grounded_mechanics_v0.json",
        "generator": {"name": "temporal_first_change_procedural_v1", "variant_count": TEMPORAL_VARIANT_COUNT},
        "timeline": {
            "duration_ms": 5200,
            "first_change_ms": first_change_ms,
            "theme": rng.randrange(6),
            "objects": objects,
        },
    }
    ground_truth = {
        "mechanic_id": "temporal_memory_first_change",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "target_object_id": target["id"],
        "target_kind": target["kind"],
        "first_change_ms": first_change_ms,
        "variant_count": TEMPORAL_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_motion_only_ghost_jigsaw(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(seed_int(seed, "motion-only-ghost-jigsaw"))
    theme = pick(rng, GHOST_PATTERN_THEMES)
    pieces = []
    for source_index in range(9):
        piece_id = f"ghost-{hashlib.sha256(f'{seed}|ghost|{source_index}'.encode('utf-8')).hexdigest()[:10]}"
        pieces.append({
            "id": piece_id,
            "source_index": source_index,
            "noise_seed": seed_int(seed, f"ghost-noise:{source_index}") % 1000003,
            "phase": round(rng.uniform(0, math.tau), 4),
        })
    rng.shuffle(pieces)
    expected_positions = {piece["id"]: int(piece["source_index"]) for piece in pieces}
    challenge_id = hashlib.sha256(f"{seed}|ghost-jigsaw".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "motion_only_ghost_jigsaw",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Reassemble the picture that exists only while it moves.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_first_five_v0.json",
        "generator": {"name": "motion_only_ghost_jigsaw_v1", "variant_count": GHOST_JIGSAW_VARIANT_COUNT},
        "visual": {
            "theme": theme,
            "frame_count": 90,
            "fps": 30,
            "scroll_speed": rng.choice((1.6, 1.8, 2.0, 2.2)),
            "global_seed": seed_int(seed, "ghost-global") % 1000003,
        },
        "pieces": pieces,
    }
    ground_truth = {
        "mechanic_id": "motion_only_ghost_jigsaw",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "expected_positions": expected_positions,
        "theme": theme,
        "variant_count": GHOST_JIGSAW_VARIANT_COUNT,
    }
    return public_state, ground_truth


def _polyline_point(vertices: list[tuple[float, float]], t: float) -> tuple[float, float]:
    segment_count = len(vertices) - 1
    scaled = clamp(t, 0.0, 0.999999) * segment_count
    index = min(segment_count - 1, int(scaled))
    local = scaled - index
    x1, y1 = vertices[index]
    x2, y2 = vertices[index + 1]
    return x1 + (x2 - x1) * local, y1 + (y2 - y1) * local


def _constellation_point(shape: str, t: float) -> tuple[float, float]:
    angle = math.tau * t
    if shape == "heart":
        x = 16 * math.sin(angle) ** 3
        y = -(13 * math.cos(angle) - 5 * math.cos(2 * angle) - 2 * math.cos(3 * angle) - math.cos(4 * angle))
        return 340 + x * 8.4, 202 + y * 7.3
    if shape == "star":
        vertices = []
        for index in range(11):
            a = -math.pi / 2 + index * math.pi / 5
            radius = 126 if index % 2 == 0 else 54
            vertices.append((340 + math.cos(a) * radius, 202 + math.sin(a) * radius))
        return _polyline_point(vertices, t)
    if shape == "spiral":
        a = math.tau * 2.65 * t
        radius = 16 + 115 * t
        return 340 + math.cos(a) * radius, 202 + math.sin(a) * radius
    if shape == "fish":
        if t < 0.72:
            a = math.tau * (t / 0.72)
            return 315 + math.cos(a) * 112, 202 + math.sin(a) * 68
        vertices = [(420, 202), (500, 140), (484, 202), (500, 264), (420, 202)]
        return _polyline_point(vertices, (t - 0.72) / 0.28)
    if shape == "umbrella":
        if t < 0.62:
            a = math.pi + math.pi * (t / 0.62)
            return 340 + math.cos(a) * 142, 218 + math.sin(a) * 104
        vertices = [(198, 218), (340, 218), (340, 322), (370, 342), (397, 318)]
        return _polyline_point(vertices, (t - 0.62) / 0.38)
    if t < 0.55:
        a = math.tau * (t / 0.55)
        return 262 + math.cos(a) * 64, 196 + math.sin(a) * 64
    vertices = [(326, 196), (482, 196), (482, 236), (452, 236), (452, 214), (416, 214), (416, 196)]
    return _polyline_point(vertices, (t - 0.55) / 0.45)


def generate_cursor_constellation_hunt(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(seed_int(seed, "cursor-constellation-hunt"))
    width, height = 680, 410
    shape = pick(rng, CONSTELLATION_SHAPES)
    solution = {"x": round(rng.uniform(110, width - 110), 2), "y": round(rng.uniform(90, height - 90), 2), "radius": 28}
    decoys = [
        {"x": round(rng.uniform(70, width - 70), 2), "y": round(rng.uniform(70, height - 70), 2)}
        for _ in range(2)
    ]
    stars = []
    for index in range(112):
        target_x, target_y = _constellation_point(shape, index / 111)
        stars.append({
            "id": f"star-{hashlib.sha256(f'{seed}|star|{index}'.encode('utf-8')).hexdigest()[:8]}",
            "base_x": round(rng.uniform(18, width - 18), 2),
            "base_y": round(rng.uniform(18, height - 18), 2),
            "target_x": round(target_x + rng.uniform(-1.8, 1.8), 2),
            "target_y": round(target_y + rng.uniform(-1.8, 1.8), 2),
            "twinkle": round(rng.uniform(0, math.tau), 3),
            "noise": False,
        })
    for index in range(26):
        stars.append({
            "id": f"noise-{hashlib.sha256(f'{seed}|noise-star|{index}'.encode('utf-8')).hexdigest()[:8]}",
            "base_x": round(rng.uniform(12, width - 12), 2),
            "base_y": round(rng.uniform(12, height - 12), 2),
            "target_x": round(rng.uniform(12, width - 12), 2),
            "target_y": round(rng.uniform(12, height - 12), 2),
            "twinkle": round(rng.uniform(0, math.tau), 3),
            "noise": True,
        })
    challenge_id = hashlib.sha256(f"{seed}|constellation".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "cursor_constellation_hunt",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Move the cursor until one clear object appears. Click its center.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_first_five_v0.json",
        "generator": {"name": "cursor_constellation_hunt_v1", "variant_count": CONSTELLATION_VARIANT_COUNT},
        "surface": {"width": width, "height": height, "solution": solution, "decoys": decoys, "stars": stars},
    }
    ground_truth = {
        "mechanic_id": "cursor_constellation_hunt",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "expected_click": solution,
        "shape": shape,
        "variant_count": CONSTELLATION_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_parallel_grillmaster(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(seed_int(seed, "parallel-grillmaster"))
    target_times = [3600, 4400, 5200, 6100, 7100, 8200]
    rng.shuffle(target_times)
    foods = []
    targets = {}
    for index, (kind, target_ms) in enumerate(zip(GRILL_FOODS, target_times)):
        food_id = f"food-{hashlib.sha256(f'{seed}|food|{kind}'.encode('utf-8')).hexdigest()[:8]}"
        tolerance_ms = rng.choice((1150, 1250, 1350))
        food = {"id": food_id, "kind": kind, "target_ms": target_ms, "tolerance_ms": tolerance_ms, "order": index}
        foods.append(food)
        targets[food_id] = {"target_ms": target_ms, "tolerance_ms": tolerance_ms, "kind": kind}
    rng.shuffle(foods)
    challenge_id = hashlib.sha256(f"{seed}|grillmaster".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "parallel_grillmaster",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Cook every item until golden, then move it to the serving tray.",
        "submit_label": "SERVE",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_first_five_v0.json",
        "generator": {"name": "parallel_grillmaster_v1", "variant_count": GRILL_VARIANT_COUNT},
        "foods": foods,
    }
    ground_truth = {
        "mechanic_id": "parallel_grillmaster",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "targets": targets,
        "variant_count": GRILL_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_rotating_keyboard(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(seed_int(seed, "rotating-keyboard"))
    target = "".join(rng.choice(ROTATING_KEYBOARD_ALPHABET) for _ in range(5))
    direction = rng.choice((-1, 1))
    duration_ms = rng.choice((8800, 9400, 10000))
    challenge_id = hashlib.sha256(f"{seed}|rotating-keyboard".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "rotating_keyboard",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or f"Confirm code {target} using the on-screen keyboard.",
        "submit_label": "CONFIRM",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_first_five_v0.json",
        "generator": {"name": "rotating_keyboard_v1", "variant_count": ROTATING_KEYBOARD_VARIANT_COUNT},
        "keyboard": {"target": target, "rows": ["23456789", "ABCDEFGHJKLM", "NPQRSTUVWXYZ"], "direction": direction, "duration_ms": duration_ms},
    }
    ground_truth = {
        "mechanic_id": "rotating_keyboard",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "target": target,
        "variant_count": ROTATING_KEYBOARD_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_slot_reel_capture(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(seed_int(seed, "slot-reel-capture"))
    max_strikes = 3
    sequence = "".join(rng.choice(SLOT_ALPHABET) for _ in range(5))
    reels = []
    for index, target in enumerate(sequence):
        symbols = list(SLOT_SYMBOLS)
        rng.shuffle(symbols)
        insert_at = rng.randrange(1, len(symbols))
        symbols.insert(insert_at, target)
        reels.append({
            "id": f"reel-{hashlib.sha256(f'{seed}|reel|{index}'.encode('utf-8')).hexdigest()[:8]}",
            "target": target,
            "tokens": symbols,
            "interval_ms": rng.randrange(360, 570, 30),
            "phase": rng.randrange(len(symbols)),
        })
    challenge_id = hashlib.sha256(f"{seed}|slot-reel".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "slot_reel_capture",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Type each letter or number while it is centered. Capture all five reels.",
        "submit_label": "VERIFY",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_first_five_v0.json",
        "generator": {"name": "slot_reel_capture_v1", "variant_count": SLOT_REEL_VARIANT_COUNT},
        "max_strikes": max_strikes,
        "reels": reels,
    }
    ground_truth = {
        "mechanic_id": "slot_reel_capture",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "sequence": sequence,
        "reel_ids": [reel["id"] for reel in reels],
        "max_strikes": max_strikes,
        "variant_count": SLOT_REEL_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_domino_autopsy(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(seed_int(seed, "domino-autopsy"))
    target_angles = [rng.choice((-6, -3, 0, 3, 6)) for _ in range(3)]
    target_slots = [
        {"x": 260 + index * 40, "y": 304, "angle": target_angles[index]}
        for index in range(3)
    ]
    loose = []
    for index, color in enumerate(DOMINO_COLORS):
        loose.append({
            "id": f"domino-{hashlib.sha256(f'{seed}|domino|{index}'.encode('utf-8')).hexdigest()[:8]}",
            "color": color,
            "x": 270 + index * 120,
            "y": 386,
            "angle": rng.choice((-72, -48, 42, 67)),
        })
    rng.shuffle(loose)
    fixed_positions = [100, 140, 180, 220, 380, 420, 460, 500]
    fixed = [
        {
            "id": f"fixed-{hashlib.sha256(f'{seed}|fixed|{index}'.encode('utf-8')).hexdigest()[:8]}",
            "x": x,
            "y": 304,
            "angle": 0,
        }
        for index, x in enumerate(fixed_positions)
    ]
    bell = {"x": 575, "y": 294}
    bell_body_id = "bell-body"
    minimum_bell_swing_radians = 0.03
    first_body_id = fixed[0]["id"]
    expected_body_ids = [item["id"] for item in fixed] + [item["id"] for item in loose]
    challenge_id = hashlib.sha256(f"{seed}|domino-autopsy".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "domino_autopsy",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Make the signal reach the bell. Test, inspect, repair.",
        "submit_label": "CERTIFY",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_second_five_v0.json",
        "generator": {"name": "domino_autopsy_v2_matter", "variant_count": DOMINO_VARIANT_COUNT},
        "board": {"width": 720, "height": 410, "fixed": fixed, "loose": loose, "bell": bell, "bell_body_id": bell_body_id, "first_body_id": first_body_id, "physics_engine": "matter-js@0.20.0"},
    }
    ground_truth = {
        "mechanic_id": "domino_autopsy",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "target_slots": target_slots,
        "loose_ids": [item["id"] for item in loose],
        "fixed_dominoes": fixed,
        "bell": bell,
        "bell_body_id": bell_body_id,
        "minimum_bell_swing_radians": minimum_bell_swing_radians,
        "first_body_id": first_body_id,
        "expected_body_ids": expected_body_ids,
        "physics_engine": "matter-js@0.20.0",
        "variant_count": DOMINO_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_consequences_boss(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("consequences_boss"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "consequences-boss"))
    scenes = []
    valid_choices = {}
    kind_choices = {}
    for scene_name, kind_choice, cruel_choice in CONSEQUENCE_SCENES:
        scene_id = f"scene-{hashlib.sha256(f'{seed}|scene|{scene_name}'.encode('utf-8')).hexdigest()[:8]}"
        scenes.append({"id": scene_id, "kind": scene_name, "choices": [kind_choice, cruel_choice]})
        valid_choices[scene_id] = [kind_choice, cruel_choice]
        kind_choices[scene_id] = kind_choice
    boss_order = [scene["id"] for scene in scenes]
    rng.shuffle(boss_order)
    challenge_id = hashlib.sha256(f"{seed}|consequences-boss".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "consequences_boss",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Make four choices. Then live with every consequence.",
        "submit_label": "FACE JUDGMENT",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_second_five_v0.json",
        "generator": {"name": "consequences_boss_v1", "variant_count": CONSEQUENCES_VARIANT_COUNT},
        "scenes": scenes,
        "boss_order": boss_order,
        "boss_actions": ["protect", "exploit"],
    }
    ground_truth = {
        "mechanic_id": "consequences_boss",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "valid_choices": valid_choices,
        "kind_choices": kind_choices,
        "boss_order": boss_order,
        "variant_count": CONSEQUENCES_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_popup_exorcist(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("popup_exorcist"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "popup-exorcist"))
    themes = list(POPUP_THEMES)
    rng.shuffle(themes)
    blocker_index = rng.randrange(2, 6)
    popups = []
    for index, theme in enumerate(themes[:7]):
        popup_id = f"popup-{hashlib.sha256(f'{seed}|popup|{index}'.encode('utf-8')).hexdigest()[:8]}"
        width = rng.randint(210, 290)
        height = rng.randint(124, 190)
        popups.append({
            "id": popup_id,
            "theme": "seal" if index == blocker_index else theme,
            "title": "END ALL PROCESSES" if index == blocker_index else theme.replace("_", " ").upper(),
            "x": rng.randint(22, 690 - width),
            "y": rng.randint(24, 360 - height),
            "w": width,
            "h": height,
            "z": index + 2,
            "special": index == blocker_index,
        })
    rng.shuffle(popups)
    blocker_id = next(item["id"] for item in popups if item["special"])
    challenge_id = hashlib.sha256(f"{seed}|popup-exorcist".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "popup_exorcist",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "End the infestation.",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_second_five_v0.json",
        "generator": {"name": "popup_exorcist_v1", "variant_count": POPUP_VARIANT_COUNT},
        "popups": popups,
    }
    ground_truth = {
        "mechanic_id": "popup_exorcist",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "popup_ids": [item["id"] for item in popups],
        "blocker_id": blocker_id,
        "variant_count": POPUP_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_funeral_ritual(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(seed_int(seed, "funeral-ritual"))
    flowers = []
    flower_patches = ((12, 78), (26, 68), (75, 69), (88, 80))
    for index, kind in enumerate(FUNERAL_FLOWER_KINDS):
        patch_x, patch_y = flower_patches[index]
        flowers.append({
            "id": f"flower-{hashlib.sha256(f'{seed}|flower|{index}'.encode('utf-8')).hexdigest()[:8]}",
            "kind": kind,
            "x": patch_x + rng.randint(-2, 2),
            "y": patch_y + rng.randint(-2, 2),
        })
    challenge_id = hashlib.sha256(f"{seed}|funeral-ritual".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "funeral_ritual",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Grieve.",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_second_five_v0.json",
        "generator": {"name": "funeral_ritual_v1", "variant_count": FUNERAL_VARIANT_COUNT},
        "epitaph": rng.choice(("MARA / SHE KEPT THE LIGHT", "ELI / HERE, AT LAST", "ORIN / BELOVED BY SMALL THINGS")),
        "moss_cells": 24,
        "brush_threshold": 17,
        "flowers": flowers,
    }
    ground_truth = {
        "mechanic_id": "funeral_ritual",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "required_events": ["inspect", "brush", "light", "gather", "offer"],
        "brush_threshold": 17,
        "moss_cells": 24,
        "flower_ids": [item["id"] for item in flowers],
        "variant_count": FUNERAL_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_slime_commute(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if has_incubator_generator("slime_commute"):
        return generate_incubator_candidate(task, seed)
    rng = random.Random(seed_int(seed, "slime-commute"))
    columns = 9
    lane_blueprints = [
        (9, "road", 1, 660, 1, [1, 4, 7]),
        (8, "road", -1, 540, 1, [0, 5]),
        (6, "water", 1, 760, 3, [0, 4, 8]),
        (5, "water", -1, 640, 2, [1, 5]),
        (3, "rail", 1, 390, 2, [2]),
        (2, "road", -1, 580, 1, [3, 7]),
    ]
    lanes = []
    for row, kind, direction, step_ms, length, offsets in lane_blueprints:
        phase = rng.randrange(columns)
        lanes.append({"row": row, "kind": kind, "direction": direction, "step_ms": step_ms, "length": length, "offsets": offsets, "phase": phase})
    start_x = rng.randrange(2, columns - 2)
    goal_x = rng.randrange(1, columns - 1)
    challenge_id = hashlib.sha256(f"{seed}|slime-commute".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": "slime_commute",
        "task_id": task["id"],
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Get home. WASD to hop.",
        "asset_manifest": "shared_runtime/assets/provenance/interaction_second_five_v0.json",
        "generator": {"name": "slime_commute_v1", "variant_count": SLIME_VARIANT_COUNT},
        "board": {"columns": columns, "rows": 11, "start_x": start_x, "goal_x": goal_x, "lanes": lanes, "max_deaths": 4},
    }
    ground_truth = {
        "mechanic_id": "slime_commute",
        "task_id": task["id"],
        "seed": seed,
        "challenge_id": challenge_id,
        "start": {"x": start_x, "y": 10},
        "goal": {"x": goal_x, "y": 0},
        "required_rows": list(range(11)),
        "max_deaths": 4,
        "variant_count": SLIME_VARIANT_COUNT,
    }
    return public_state, ground_truth


def generate_unavailable(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    metadata = task.get("metadata") or {}
    mechanic_id = metadata.get("mechanic_id", "unknown")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": mechanic_id,
        "task_id": task.get("id"),
        "status": "not_benchmark_ready",
    }
    ground_truth = {
        "mechanic_id": mechanic_id,
        "task_id": task.get("id"),
        "seed": seed,
        "status": "not_benchmark_ready",
    }
    return public_state, ground_truth


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    os.replace(tmp, path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare one Weird CAPTCHA Gym task.")
    parser.add_argument("--task-json", required=True)
    parser.add_argument("--seed")
    parser.add_argument("--state-dir", default=str(STATE_DIR))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    task_path = Path(args.task_json)
    task = load_task(task_path)
    seed = challenge_seed(task, args.seed)
    mechanic_id = (task.get("metadata") or {}).get("mechanic_id")
    if mechanic_id == "surreal_apple_on_tree_grid":
        public_state, ground_truth = generate_surreal_apple_on_tree_grid(task, seed)
    elif mechanic_id == "cursor_lens_reveal":
        public_state, ground_truth = generate_cursor_lens_reveal(task, seed)
    elif mechanic_id == "board_game_captcha":
        public_state, ground_truth = generate_board_game_captcha(task, seed)
    elif mechanic_id == "modifier_stack_image_grid":
        public_state, ground_truth = generate_modifier_stack_image_grid(task, seed)
    elif mechanic_id == "semantic_drag_drop_absurdity":
        public_state, ground_truth = generate_semantic_drag_drop_absurdity(task, seed)
    elif mechanic_id == "reload_interruption":
        public_state, ground_truth = generate_reload_interruption(task, seed)
    elif mechanic_id == "rotate_wrong_thing_upright":
        public_state, ground_truth = generate_rotate_wrong_thing_upright(task, seed)
    elif mechanic_id == "bureaucratic_signature_trap":
        public_state, ground_truth = generate_bureaucratic_signature_trap(task, seed)
    elif mechanic_id == "wonky_text_hostile_rendering":
        public_state, ground_truth = generate_wonky_text_hostile_rendering(task, seed)
    elif mechanic_id == "temporal_memory_first_change":
        public_state, ground_truth = generate_temporal_memory_first_change(task, seed)
    elif mechanic_id == "motion_only_ghost_jigsaw":
        public_state, ground_truth = generate_motion_only_ghost_jigsaw(task, seed)
    elif mechanic_id == "cursor_constellation_hunt":
        public_state, ground_truth = generate_cursor_constellation_hunt(task, seed)
    elif mechanic_id == "parallel_grillmaster":
        public_state, ground_truth = generate_parallel_grillmaster(task, seed)
    elif mechanic_id == "rotating_keyboard":
        public_state, ground_truth = generate_rotating_keyboard(task, seed)
    elif mechanic_id == "slot_reel_capture":
        public_state, ground_truth = generate_slot_reel_capture(task, seed)
    elif mechanic_id == "domino_autopsy":
        public_state, ground_truth = generate_domino_autopsy(task, seed)
    elif mechanic_id == "consequences_boss":
        public_state, ground_truth = generate_consequences_boss(task, seed)
    elif mechanic_id == "popup_exorcist":
        public_state, ground_truth = generate_popup_exorcist(task, seed)
    elif mechanic_id == "funeral_ritual":
        public_state, ground_truth = generate_funeral_ritual(task, seed)
    elif mechanic_id == "slime_commute":
        public_state, ground_truth = generate_slime_commute(task, seed)
    elif has_incubator_generator(mechanic_id):
        public_state, ground_truth = generate_incubator_candidate(task, seed)
    else:
        public_state, ground_truth = generate_unavailable(task, seed)

    state_dir = Path(args.state_dir)
    write_json(state_dir / "current_task.json", {"task": task, "seed": seed, "base_seed": seed, "attempt": 0})
    write_json(state_dir / "public_state.json", public_state)
    write_json(state_dir / "ground_truth.json", ground_truth)
    for stale in (state_dir / "result.json", Path("/tmp/task_result.json")):
        try:
            stale.unlink()
        except FileNotFoundError:
            pass
    print(f"prepared {task.get('id')} mechanic={mechanic_id} seed={seed}")


if __name__ == "__main__":
    main()
