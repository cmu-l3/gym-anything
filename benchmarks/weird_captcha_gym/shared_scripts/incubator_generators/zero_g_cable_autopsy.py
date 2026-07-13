from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "zero_g_cable_autopsy"
PALETTES = ("ultraviolet-lab", "sterile-cyan", "amber-vacuum", "oxide-orbit")
# 2 cable windings × 3 ring heights × 3 peg radii × 4 palettes.
# Challenge identifiers and cosmetic case numbers are intentionally not counted.
VARIANT_COUNT = 2 * 3 * 3 * 4


def _seed_int(seed: str, salt: str) -> int:
    return int(hashlib.sha256(f"{seed}|{salt}".encode()).hexdigest()[:16], 16)


def _round(value: float, digits: int = 5) -> float:
    return round(float(value) + 1e-12, digits)


def _distance(first: list[float], second: list[float]) -> float:
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(first, second)))


def _segment_distance(point: list[float], first: list[float], second: list[float]) -> float:
    segment=[second[i]-first[i] for i in range(3)];denom=sum(value*value for value in segment)
    amount=0.0 if denom<1e-12 else max(0.0,min(1.0,sum((point[i]-first[i])*segment[i] for i in range(3))/denom))
    return _distance(point,[first[i]+segment[i]*amount for i in range(3)])


def _torus_distance(point: list[float],ring: dict[str,Any]) -> float:
    relative=[point[i]-ring["center"][i] for i in range(3)];axial=sum(relative[i]*ring["normal"][i] for i in range(3));plane=[relative[i]-ring["normal"][i]*axial for i in range(3)]
    return math.hypot(math.sqrt(sum(value*value for value in plane))-float(ring["radius"]),axial)


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:12]
    task_id = str(task.get("id") or "zero_g_cable_autopsy_seed_0001@0.1")
    sign = rng.choice((-1, 1))
    ring_height = rng.choice((1.5, 1.75, 2.0))
    peg_radius = rng.choice((0.68, 0.72, 0.76))
    nodes: list[list[float]] = []
    for index in range(9):
        x = -3.0 + index * 0.75
        centered = abs(index - 4) / 4.0
        z = sign * (1.05 * (1.0 - centered**1.45))
        nodes.append([_round(x), 0.0, _round(z)])
    rest_lengths = [_round(_distance(nodes[index], nodes[index + 1])) for index in range(8)]
    peg = {"id": "central-peg", "center": [0.0, 0.0, 0.0], "radius": peg_radius}
    pegs = [
        peg,
        {"id": "lower-left", "center": [-1.45, -0.3, -sign * 0.86], "radius": 0.46},
        {"id": "lower-right", "center": [1.45, -0.3, -sign * 0.86], "radius": 0.46},
    ]
    rings = [
        {"id": "port-ring", "center": [-3.72, ring_height, 0.0], "normal": [-1.0, 0.0, 0.0], "radius": 0.78, "tube_radius": 0.12, "endpoint_index": 0},
        {"id": "starboard-ring", "center": [3.72, ring_height, 0.0], "normal": [1.0, 0.0, 0.0], "radius": 0.78, "tube_radius": 0.12, "endpoint_index": 8},
    ]
    contacts = [
        {"id": "alarm-low", "center": [0.0, 0.15, -sign * 1.42], "radius": 0.28},
        {"id": "alarm-high", "center": [0.9, 1.0, -sign * 1.24], "radius": 0.25},
    ]
    controls = {
        "move_step": 0.25, "pbd_substeps": 4, "constraint_iterations": 8,
        "damping": 0.985, "cable_radius": 0.09, "attachment_pick_radius_px": 24,
        "orbit_yaw_step_deg": 15, "orbit_pitch_step_deg": 10,
        "world_bounds": {"x": [-5.0, 5.0], "y": [-2.0, 4.2], "z": [-3.0, 3.0]},
    }
    qualification = {
        "maximum_client_node_error": 0.018, "minimum_dual_ticks": 8,
        "maximum_final_winding": 0.12, "minimum_total_substeps": 40,
    }
    camera = {"yaw_deg": -18, "pitch_deg": -10, "distance": 10.5, "target": [0.0, 0.65, 0.0], "fov_deg": 48}
    public_state = {
        "benchmark": "weird_captcha_gym", "mechanic_id": MECHANIC_ID, "task_id": task_id,
        "challenge_id": challenge_id, "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt": task.get("natural_language") or "Free the cable using both grippers. Do not touch the red contacts.",
        "generator": {"name": "zero_gravity_pbd_cable_v1", "variant_count": VARIANT_COUNT, "variant_count_kind": "discrete_geometry_and_palette"},
        "case_id": f"ZG-{challenge_id[:4].upper()}-{rng.randint(100,999)}", "palette": rng.choice(PALETTES),
        "canvas": {"width": 900, "height": 470}, "nodes": nodes, "rest_lengths": rest_lengths,
        "pegs": pegs, "rings": rings, "contacts": contacts, "controls": controls,
        "qualification": qualification, "initial_camera": camera, "submit_label": "SEAL AUTOPSY",
    }
    up_moves = int(round(ring_height / controls["move_step"]))
    outward_moves = int(math.ceil((3.72 + 0.22 - 3.0) / controls["move_step"]))
    ground_truth = {
        "mechanic_id": MECHANIC_ID, "task_id": task_id, "seed": seed, "challenge_id": challenge_id,
        "canvas": public_state["canvas"], "nodes": nodes, "rest_lengths": rest_lengths,
        "pegs": pegs, "rings": rings, "contacts": contacts, "controls": controls,
        "qualification": qualification, "initial_camera": camera,
        "solution": {
            "attachments": {"A": 0, "B": 8}, "up_moves": up_moves, "outward_moves": outward_moves,
            "moves": [
                {"gripper": "A", "axis": "y", "delta": controls["move_step"], "count": up_moves},
                {"gripper": "B", "axis": "y", "delta": controls["move_step"], "count": up_moves},
                {"gripper": "A", "axis": "x", "delta": -controls["move_step"], "count": outward_moves},
                {"gripper": "B", "axis": "x", "delta": controls["move_step"], "count": outward_moves},
            ],
        },
        "variant_count": VARIANT_COUNT,
    }
    assert abs(sum(rest_lengths) - sum(_distance(nodes[i], nodes[i + 1]) for i in range(8))) < 1e-4
    cable_radius=float(controls["cable_radius"])
    assert all(_segment_distance(contact["center"],first,second)>float(contact["radius"])+cable_radius+.15 for first,second in zip(nodes,nodes[1:]) for contact in contacts)
    assert all(_segment_distance(peg_item["center"],first,second)>float(peg_item["radius"])+cable_radius+.05 for first,second in zip(nodes,nodes[1:]) for peg_item in pegs)
    assert all(_torus_distance([first[axis]+(second[axis]-first[axis])*sample/16 for axis in range(3)],ring)>float(ring["tube_radius"])+cable_radius+.05 for first,second in zip(nodes,nodes[1:]) for ring in rings for sample in range(17))
    return public_state, ground_truth
