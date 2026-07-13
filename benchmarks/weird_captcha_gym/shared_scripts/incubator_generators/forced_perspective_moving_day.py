from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "forced_perspective_moving_day"


def _seed(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    mirror = rng.choice((-1, 1))
    focal = rng.choice((460, 500, 540))
    yaw = round(rng.choice((-1, 1)) * rng.uniform(0.018, 0.042), 6)
    palettes = (
        {"sky": "#d9ecda", "floor": "#d0c9b4", "wall": "#27332b", "sign": "#f5cf58", "crate": "#8ce67f", "void": "#151421", "alert": "#e85b54"},
        {"sky": "#dbe5ef", "floor": "#c9c2af", "wall": "#24323c", "sign": "#ffb85e", "crate": "#72ddc6", "void": "#121521", "alert": "#f06465"},
        {"sky": "#eee3cf", "floor": "#c9bba5", "wall": "#382d28", "sign": "#f1d565", "crate": "#91e27b", "void": "#17131d", "alert": "#e75d58"},
    )
    palette = rng.choice(palettes)
    camera = {"x": 0.0, "y": 1.6, "z": 2.0, "yaw": yaw, "focal": focal, "center": [490, 165], "near": 0.6}
    objects = [
        {"id": "sign", "role": "bridge", "center": [-2.2 * mirror, 1.1, 6.5], "scale": 1.0, "base_size": [1.3, 2.2, 0.18], "reference_size": 1.3, "orientation": "upright"},
        {"id": "crate", "role": "key", "center": [2.4 * mirror, 0.7, 8.0], "scale": 1.0, "base_size": [1.4, 1.4, 1.4], "reference_size": 1.4, "orientation": "box"},
    ]
    slot = {"id": "key-slot", "center": [1.75 * mirror, 4.65], "size": [1.6, 1.7], "max_scale": 0.56}
    bridge_zone = {"id": "void-bridge", "center": [0, 13.25], "size": [3.4, 3.5], "min_scale": 2.0}
    world = {
        "x_bounds": [-6, 6], "z_bounds": [0, 24], "gap": [11.5, 15.0],
        "door": {"z": 19, "thickness": 0.65, "half_gap": 1.25}, "exit_z": 22.4,
        "avatar_radius": 0.34, "move_step": 0.32, "tick_ms": 50,
    }
    depth_controls = {"minimum": 2.0, "maximum": 13.5, "step": 0.5}
    task_id = str(task.get("id") or "forced_perspective_moving_day_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:12]
    public = {
        "benchmark": "weird_captcha_gym", "mechanic_id": MECHANIC_ID, "task_id": task_id, "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Resize the available objects through perspective and move the shipment through the impossible doorway.",
        "submit_label": "CERTIFY IMPOSSIBLE MOVE", "stage": {"width": 980, "height": 480},
        "camera": camera, "world": world, "objects": objects, "slot": slot, "bridge_zone": bridge_zone, "palette": palette,
        "depth_controls": depth_controls,
        "requirements": {"pick_radius_px": 34, "projection_tolerance": 0.08, "max_movement_events": 180},
        "clearance_audit": {"bridge_required_depth": 4.38, "bridge_worst_case_length": 5.1, "bridge_width_margin": 0.5, "door_gap_margin": 0.57, "slot_scale_margin": 0.04},
        "generator": {"name": "ray_plane_apparent_scale_room_v1", "variant_count": 11_600_000_000},
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
    }
    truth = {**public, "seed": seed, "mirror": mirror,
             "solver_targets": {"crate": [slot["center"][0], slot["center"][1]], "sign": [bridge_zone["center"][0], bridge_zone["center"][1]]}}
    sign_depth = math.cos(yaw) * (bridge_zone["center"][1] - camera["z"]) + math.sin(yaw) * (bridge_zone["center"][0] - camera["x"])
    sign_initial_depth = math.cos(yaw) * (objects[0]["center"][2] - camera["z"]) + math.sin(yaw) * (objects[0]["center"][0] - camera["x"])
    resulting_scale = sign_depth / sign_initial_depth
    assert resulting_scale >= bridge_zone["min_scale"] + 0.25
    worst_rounded_scale = (sign_depth - depth_controls["step"] / 2) / sign_initial_depth
    required_support_length = world["gap"][1] - world["gap"][0] + 2 * world["avatar_radius"] + 0.20 + depth_controls["step"]
    assert objects[0]["base_size"][1] * worst_rounded_scale >= required_support_length
    crate_depth = math.cos(yaw) * (slot["center"][1] - camera["z"]) + math.sin(yaw) * (slot["center"][0] - camera["x"])
    crate_initial_depth = math.cos(yaw) * (objects[1]["center"][2] - camera["z"]) + math.sin(yaw) * (objects[1]["center"][0] - camera["x"])
    assert crate_depth / crate_initial_depth <= slot["max_scale"] - 0.08
    return public, truth
