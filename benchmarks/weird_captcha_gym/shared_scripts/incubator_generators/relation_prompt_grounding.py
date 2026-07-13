from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "relation_prompt_grounding"
STAGE_WIDTH = 900
STAGE_HEIGHT = 430
SETTLE_TICKS = 8
TEMPLATES = (
    ("orb", "BRASS ORB", 30, False, "amber"),
    ("prism", "CYAN PRISM", 34, False, "cyan"),
    ("disk", "RED DISK", 31, False, "red"),
    ("star", "BLACK STAR", 32, False, "black"),
    ("frame", "IVORY FRAME", 72, True, "ivory"),
)


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def _constraint_text(kind: str, a_label: str, b_label: str) -> str:
    labels = {
        "left_of": f"{a_label} must finish LEFT OF {b_label}.",
        "right_of": f"{a_label} must finish RIGHT OF {b_label}.",
        "inside": f"{a_label} must finish INSIDE {b_label}.",
        "in_front_of": f"{a_label} must finish IN FRONT OF {b_label} on the depth rail.",
        "behind": f"{a_label} must finish BEHIND {b_label} on the depth rail.",
        "touching": f"{a_label} must finish TOUCHING {b_label}.",
        "not_touching": f"{a_label} must finish NOT TOUCHING {b_label}.",
    }
    return labels[kind]


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    templates = list(TEMPLATES)
    rng.shuffle(templates)
    phase_offset = rng.randrange(32)
    carousel_phases = [(phase_offset + slot) % 32 for slot in (0, 6, 12, 19, 25)]
    rng.shuffle(carousel_phases)
    objects: list[dict[str, Any]] = []
    for index, (shape, label, radius, container, color) in enumerate(templates):
        object_id = f"object-{hashlib.sha256(f'{seed}|{shape}'.encode('utf-8')).hexdigest()[:8]}"
        objects.append({
            "id": object_id,
            "label": label,
            "shape": shape,
            "radius": radius,
            "container": container,
            "color": color,
            "carousel_phase": carousel_phases[index],
            "initial_depth": 50,
        })

    by_shape = {item["shape"]: item for item in objects}
    movable = [item for item in objects if not item["container"]]
    rng.shuffle(movable)
    a, b, inner, e = movable
    frame = by_shape["frame"]
    horizontal_kind = rng.choice(("left_of", "right_of"))
    depth_kind = rng.choice(("in_front_of", "behind"))
    contact_kind = rng.choice(("touching", "not_touching"))
    optional = rng.sample(("horizontal", "inside", "contact"), 2)
    relation_kinds = ["depth", *optional]
    rng.shuffle(relation_kinds)

    definitions = {
        "horizontal": (horizontal_kind, a, b),
        "inside": ("inside", inner, frame),
        "depth": (depth_kind, e, a),
        "contact": (contact_kind, e, b),
    }
    constraints = []
    for relation_kind in relation_kinds:
        kind, first, second = definitions[relation_kind]
        constraints.append({
            "type": kind,
            "a": first["id"],
            "b": second["id"],
            "text": _constraint_text(kind, first["label"], second["label"]),
        })

    positions: dict[str, dict[str, int]] = {
        a["id"]: {"x": 430, "y": 118, "depth": 50},
        b["id"]: {"x": 690, "y": 118, "depth": 50},
        inner["id"]: {"x": 638, "y": 310, "depth": 50},
        frame["id"]: {"x": 638, "y": 310, "depth": 50},
        e["id"]: {"x": 440, "y": 320, "depth": 50},
    }
    if horizontal_kind == "right_of":
        positions[a["id"]]["x"], positions[b["id"]]["x"] = positions[b["id"]]["x"], positions[a["id"]]["x"]
    if "inside" not in optional:
        positions[inner["id"]] = {"x": 520, "y": 305, "depth": 50}
    if "contact" in optional:
        if contact_kind == "touching":
            bx, by = positions[b["id"]]["x"], positions[b["id"]]["y"]
            distance = b["radius"] + e["radius"]
            ex = bx + distance
            if ex > 835:
                ex = bx - distance
            positions[e["id"]]["x"], positions[e["id"]]["y"] = ex, by
        else:
            positions[e["id"]]["x"], positions[e["id"]]["y"] = 800, 330
    if depth_kind == "in_front_of":
        positions[e["id"]]["depth"], positions[a["id"]]["depth"] = 84, 18
    else:
        positions[e["id"]]["depth"], positions[a["id"]]["depth"] = 18, 84

    settle_vectors = {
        item["id"]: {"dx": rng.randint(-3, 3), "dy": rng.randint(-2, 2)}
        for item in objects
    }
    if "inside" in optional:
        settle_vectors[inner["id"]] = dict(settle_vectors[frame["id"]])
    if "contact" in optional and contact_kind == "touching":
        settle_vectors[e["id"]] = dict(settle_vectors[b["id"]])

    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "relation_prompt_grounding_seed_0001@0.1")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Assemble the objects so the posted relation contract survives settling.",
        "submit_label": "CERTIFY STABLE GRAPH",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "dynamic_relation_assembly_v1", "variant_count": 5_000_000_000},
        "stage": {"width": STAGE_WIDTH, "height": STAGE_HEIGHT},
        "carousel": {"center": [172, 210], "radius_x": 116, "radius_y": 128, "ticks": 32, "tick_ms": 95},
        "worktable_rect": {"x": 338, "y": 34, "width": 536, "height": 360},
        "objects": objects,
        "constraints": constraints,
        "settle_vectors": settle_vectors,
        "settle_ticks": SETTLE_TICKS,
        "settle_tick_ms": 110,
        "rules": {
            "horizontal_gap": 80,
            "depth_gap": 24,
            "touch_tolerance": 17,
            "not_touch_gap": 38,
            "inside_inset": 8,
        },
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": public_state["stage"],
        "carousel": public_state["carousel"],
        "worktable_rect": public_state["worktable_rect"],
        "objects": objects,
        "constraints": constraints,
        "settle_vectors": settle_vectors,
        "settle_ticks": SETTLE_TICKS,
        "rules": public_state["rules"],
        "solution_positions": positions,
        "variant_count": public_state["generator"]["variant_count"],
    }
    assert len(objects) == 5 and len(constraints) == 3
    assert any(item["type"] in {"in_front_of", "behind"} for item in constraints)
    assert all(math.isfinite(value) for state in positions.values() for value in state.values())
    return public_state, ground_truth
