from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "bomb_manual_from_hell"
WIRE_COLORS = ("crimson", "amber", "cobalt", "ivory", "violet", "jade", "coral", "slate", "copper")
PLATE_SPECS = (
    ("plate-cyan", "CYAN", "#63e7dc"),
    ("plate-amber", "AMBER", "#f5b94c"),
    ("plate-magenta", "MAGENTA", "#ee75bd"),
    ("plate-lime", "LIME", "#a8e76d"),
    ("plate-indigo", "INDIGO", "#8b8df2"),
)
ANCHOR_LAYOUTS = (
    (("triangle", -142, -96), ("square", 124, -73), ("circle", -38, 112)),
    (("triangle", -126, 88), ("square", 139, 74), ("circle", 24, -116)),
    (("triangle", -151, 24), ("square", 72, 118), ("circle", 136, -91)),
    (("triangle", 138, -24), ("square", -92, 116), ("circle", -132, -88)),
    (("triangle", 38, 118), ("square", -148, -38), ("circle", 128, -102)),
)
ANGLE_STEP = 45
PLATE_WIDTH = 420
PLATE_HEIGHT = 330


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _transform(x: float, y: float, pose: dict[str, Any]) -> tuple[float, float]:
    if bool(pose["flipped"]):
        x = -x
    angle = math.radians(float(pose["angle_deg"]))
    cosine, sine = math.cos(angle), math.sin(angle)
    return (
        float(pose["x"]) + x * cosine - y * sine,
        float(pose["y"]) + x * sine + y * cosine,
    )


def _inverse_transform(x: float, y: float, pose: dict[str, Any]) -> tuple[float, float]:
    dx, dy = x - float(pose["x"]), y - float(pose["y"])
    angle = -math.radians(float(pose["angle_deg"]))
    cosine, sine = math.cos(angle), math.sin(angle)
    local_x = dx * cosine - dy * sine
    local_y = dx * sine + dy * cosine
    if bool(pose["flipped"]):
        local_x = -local_x
    return local_x, local_y


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    colors = list(WIRE_COLORS)
    rng.shuffle(colors)
    wires: list[dict[str, Any]] = []
    for index in range(9):
        wire_id = f"wire-{index + 1}-{hashlib.sha256(f'{seed}|wire|{index}'.encode('utf-8')).hexdigest()[:7]}"
        wires.append(
            {
                "id": wire_id,
                "slot": index,
                "y": 75 + index * 42,
                "color": colors[index],
                "striped": bool(rng.getrandbits(1)),
            }
        )
    correct_index = rng.randrange(len(wires))
    correct_wire_id = wires[correct_index]["id"]
    decoys = [wire["id"] for wire in wires if wire["id"] != correct_wire_id]
    rng.shuffle(decoys)
    aperture_sets = tuple(
        [correct_wire_id, *(decoys[(index * 2 + offset) % len(decoys)] for offset in range(4))]
        for index in range(len(PLATE_SPECS))
    )
    wire_map = {wire["id"]: wire for wire in wires}
    observation_x = 392
    plates: list[dict[str, Any]] = []
    target_poses: dict[str, dict[str, Any]] = {}
    for index, ((plate_id, label, color), anchor_layout, aperture_ids) in enumerate(
        zip(PLATE_SPECS, ANCHOR_LAYOUTS, aperture_sets)
    ):
        target_pose = {
            "x": 360 + rng.randint(-15, 15),
            "y": 250 + rng.randint(-12, 12),
            "angle_deg": rng.randrange(0, 360, ANGLE_STEP),
            "flipped": bool(rng.getrandbits(1)),
        }
        target_poses[plate_id] = target_pose
        anchors = [
            {"shape": shape, "x": x, "y": y}
            for shape, x, y in anchor_layout
        ]
        pins = []
        for anchor in anchors:
            point = _transform(float(anchor["x"]), float(anchor["y"]), target_pose)
            pins.append({"shape": anchor["shape"], "x": round(point[0], 3), "y": round(point[1], 3)})
        apertures = []
        for wire_id in aperture_ids:
            wire = wire_map[wire_id]
            point = _inverse_transform(observation_x, float(wire["y"]), target_pose)
            apertures.append({"wire_id": wire_id, "x": round(point[0], 3), "y": round(point[1], 3)})
        initial_angle = rng.randrange(0, 360, ANGLE_STEP)
        initial_flipped = bool(rng.getrandbits(1))
        plates.append(
            {
                "id": plate_id,
                "label": label,
                "color": color,
                "width": PLATE_WIDTH,
                "height": PLATE_HEIGHT,
                "anchors": anchors,
                "pins": pins,
                "apertures": apertures,
                "initial_pose": {
                    "x": 775 + index * 5,
                    "y": 214 + index * 13,
                    "angle_deg": initial_angle,
                    "flipped": initial_flipped,
                },
            }
        )

    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "bomb_manual_from_hell_seed_0001@0.1")
    requirements = {
        "rotation_step_deg": ANGLE_STEP,
        "snap_tolerance_px": 24,
        "aperture_radius_px": 21,
        "plate_count": len(plates),
    }
    stage = {"width": 900, "height": 500, "device": {"x": 34, "y": 36, "width": 662, "height": 428}}
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Register all five transparent manual plates, then cut the only wire left exposed.",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "generator": {"name": "bomb_manual_acetate_v3", "variant_count": 98_205_696_000},
        "stage": stage,
        "wires": wires,
        "plates": plates,
        "requirements": requirements,
        "observation_x": observation_x,
        "submit_label": "CUT SELECTED WIRE",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": stage,
        "wires": wires,
        "plates": plates,
        "requirements": requirements,
        "observation_x": observation_x,
        "target_poses": target_poses,
        "correct_wire_id": correct_wire_id,
        "correct_wire_index": correct_index,
        "variant_count": 98_205_696_000,
    }
    assert len(plates) == 5 and len(wires) == 9
    assert set.intersection(*(set(items) for items in aperture_sets)) == {correct_wire_id}
    for plate in plates:
        assert len(plate["anchors"]) == 3 and len(plate["pins"]) == 3 and len(plate["apertures"]) == 5
    return public_state, ground_truth
