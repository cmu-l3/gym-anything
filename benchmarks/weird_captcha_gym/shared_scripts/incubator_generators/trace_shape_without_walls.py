from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "trace_shape_without_walls"
STAGE_WIDTH = 1000
STAGE_HEIGHT = 440


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def _catmull_rom(control: list[tuple[float, float]], samples_per_segment: int) -> list[list[int]]:
    if len(control) < 2:
        raise ValueError("a spline requires at least two control points")
    padded = [control[0], *control, control[-1]]
    points: list[list[int]] = []
    for segment in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[segment - 1 : segment + 3]
        for sample in range(samples_per_segment):
            t = sample / samples_per_segment
            t2, t3 = t * t, t * t * t
            x = 0.5 * (
                2 * p1[0]
                + (-p0[0] + p2[0]) * t
                + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
            )
            y = 0.5 * (
                2 * p1[1]
                + (-p0[1] + p2[1]) * t
                + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
            )
            point = [round(x), round(y)]
            if not points or point != points[-1]:
                points.append(point)
    endpoint = [round(control[-1][0]), round(control[-1][1])]
    if points[-1] != endpoint:
        points.append(endpoint)
    return points


def _path_length(points: list[list[int]]) -> float:
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:]))


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    xs = (72, 178, 292, 408, 530, 650, 770, 928)
    y = rng.randint(150, 290)
    controls: list[tuple[float, float]] = []
    for index, x in enumerate(xs):
        if index == 0:
            current = y
        elif index == len(xs) - 1:
            current = rng.randint(145, 295)
        else:
            current = max(92, min(348, y + rng.randint(-94, 94)))
            y = current
        controls.append((x, current))
    main_path = _catmull_rom(controls, 13)

    branch_count = rng.choice((3, 4))
    attach_fractions = rng.sample((0.24, 0.38, 0.53, 0.68, 0.79), branch_count)
    attach_fractions.sort()
    branches: list[dict[str, Any]] = []
    for number, fraction in enumerate(attach_fractions, start=1):
        attach_index = round((len(main_path) - 1) * fraction)
        attach = main_path[attach_index]
        room_above = attach[1] - 46
        room_below = STAGE_HEIGHT - 46 - attach[1]
        if abs(room_above - room_below) < 35:
            direction = -1 if (number + rng.randrange(2)) % 2 else 1
        else:
            direction = -1 if room_above > room_below else 1
        vertical = min(145, max(92, (room_above if direction < 0 else room_below) - 8))
        bend = rng.choice((-1, 1))
        branch_control = [
            (attach[0], attach[1]),
            (attach[0] + rng.randint(24, 52), attach[1] + direction * 45),
            (attach[0] + bend * rng.randint(18, 54), attach[1] + direction * int(vertical * 0.78)),
            (max(54, min(946, attach[0] + bend * rng.randint(58, 105))), attach[1] + direction * vertical),
        ]
        branch_points = _catmull_rom(branch_control, 9)
        branches.append({
            "id": f"echo-{number}-{hashlib.sha256(f'{seed}|branch|{number}'.encode()).hexdigest()[:5]}",
            "attach_index": attach_index,
            "points": branch_points,
        })

    checkpoint_count = 11
    checkpoint_indices = sorted({round(index * (len(main_path) - 1) / (checkpoint_count - 1)) for index in range(checkpoint_count)})
    if checkpoint_indices[0] != 0:
        checkpoint_indices.insert(0, 0)
    if checkpoint_indices[-1] != len(main_path) - 1:
        checkpoint_indices.append(len(main_path) - 1)

    corridor_radius = rng.randint(36, 41)
    sonar_radius = rng.randint(71, 79)
    path_length = _path_length(main_path)
    drift = {
        "amplitude_x": rng.randint(10, 14),
        "amplitude_y": rng.randint(8, 12),
        "rate_x": round(rng.uniform(0.060, 0.078), 5),
        "rate_y": round(rng.uniform(0.047, 0.066), 5),
        "phase_x": round(rng.uniform(0.1, math.pi * 1.8), 5),
        "phase_y": round(rng.uniform(0.1, math.pi * 1.8), 5),
    }
    requirements = {
        "min_probe_samples": 24,
        "min_probe_cells": 14,
        "min_main_coverage": min(58, round(len(main_path) * 0.62)),
        "min_branch_coverage": min(3, branch_count),
        "min_trace_samples": max(62, round(len(main_path) * 0.78)),
        "min_trace_distance": round(path_length * 0.83),
        "min_trace_ms": 620,
        "max_raw_step": 58,
    }
    task_id = str(task.get("id") or "trace_shape_without_walls_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Map the hidden corridor with sonar, then hold from START and trace continuously to EXIT.",
        "submit_label": "CERTIFY TRACE RECORD",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "blind_corridor_oscilloscope_v1", "variant_count": 8_600_000_000},
        "stage": {"width": STAGE_WIDTH, "height": STAGE_HEIGHT},
        "main_path": main_path,
        "branches": branches,
        "start": main_path[0],
        "exit": main_path[-1],
        "checkpoint_indices": checkpoint_indices,
        "corridor_radius": corridor_radius,
        "sonar_radius": sonar_radius,
        "sonar_fade_ms": 780,
        "drift": drift,
        "requirements": requirements,
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": public_state["stage"],
        "main_path": main_path,
        "branches": branches,
        "start": public_state["start"],
        "exit": public_state["exit"],
        "checkpoint_indices": checkpoint_indices,
        "corridor_radius": corridor_radius,
        "sonar_radius": sonar_radius,
        "drift": drift,
        "requirements": requirements,
        "path_length": path_length,
        "variant_count": public_state["generator"]["variant_count"],
    }
    assert 3 <= len(branches) <= 4
    assert len(main_path) >= 80
    assert all(38 <= x <= STAGE_WIDTH - 38 and 38 <= y <= STAGE_HEIGHT - 38 for x, y in main_path)
    assert all(34 <= x <= STAGE_WIDTH - 34 and 34 <= y <= STAGE_HEIGHT - 34 for branch in branches for x, y in branch["points"])
    return public_state, ground_truth
