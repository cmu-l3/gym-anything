from __future__ import annotations

import copy
import hashlib
import random
from typing import Any


MECHANIC_ID = "surreal_apple_on_tree_grid"
STAGE = {"width": 960, "height": 520}
VIEW_LIMIT = 62
VARIANT_COUNT = 8_600_000_000


def _seed(seed: str) -> int:
    return int(hashlib.sha256(f"{seed}|{MECHANIC_ID}|parallax-v2".encode()).hexdigest()[:16], 16)


def _project(point: list[float], angle_deg: float) -> list[float]:
    import math

    angle = math.radians(angle_deg)
    x, y, z = point
    return [
        round(430 + x * math.cos(angle) + z * math.sin(angle), 2),
        round(246 + y + 0.10 * z * math.cos(angle) - 0.05 * x * math.sin(angle), 2),
    ]


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed(seed))
    task_id = str(task.get("id") or "surreal_apple_on_tree_grid_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:13]
    attached_indexes = set(rng.sample(range(5), 3))
    xs = [-250, -132, -8, 126, 248]
    ys = [-64, -134, -164, -118, -54]
    rng.shuffle(ys)
    apples: list[dict[str, Any]] = []
    branches: list[dict[str, Any]] = []
    for index, (x, y) in enumerate(zip(xs, ys)):
        z = rng.randint(-125, 125)
        apple_id = f"fruit-{hashlib.sha256(f'{seed}|fruit|{index}'.encode()).hexdigest()[:7]}"
        apples.append({
            "id": apple_id,
            "position": [x + rng.randint(-7, 7), y, z],
            "radius": rng.randint(20, 24),
            "hue": rng.choice(("ruby", "gold", "rose")),
            "scar": rng.randint(0, 3),
        })
        fruit = apples[-1]
        fx, fy, fz = fruit["position"]
        tip_z = fz if index in attached_indexes else fz + rng.choice((-1, 1)) * rng.randint(68, 112)
        # At the head-on view a detached branch tip has the same projection as
        # the apple stem. Orbiting exposes the real depth separation.
        tip_y = fy - 28 - 0.10 * (tip_z - fz)
        side = -1 if fx < 0 else 1
        branches.append({
            "id": f"limb-{index + 1}",
            "fruit_id": apple_id,
            "points": [
                [side * 18, 92 - index * 15, rng.randint(-35, 35)],
                [fx * 0.40, fy * 0.18 + 42, round((tip_z + fz) * 0.18)],
                [fx * 0.74, fy * 0.63, round((tip_z + fz) * 0.52)],
                [fx, round(tip_y, 2), tip_z],
            ],
        })

    rng.shuffle(apples)
    basket = {"x": 762, "y": 358, "width": 172, "height": 132}
    requirements = {
        "minimum_orbit_span_deg": 96,
        "minimum_orbit_travel_deg": 155,
        "minimum_view_sectors": 4,
        "minimum_orbit_samples": 18,
        "minimum_pluck_moves": 4,
        "minimum_pluck_ms": 90,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": "Orbit the impossible orchard. Pluck only fruit whose stem is joined to wood in depth.",
        "submit_label": "SEAL THE HARVEST",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "analytic_parallax_orchard_v2", "variant_count": VARIANT_COUNT},
        "stage": STAGE,
        "view_limit_deg": VIEW_LIMIT,
        "initial_angle_deg": 0,
        "apples": copy.deepcopy(apples),
        "branches": copy.deepcopy(branches),
        "basket": basket,
        "requirements": requirements,
    }
    attached_ids = [branch["fruit_id"] for index, branch in enumerate(branches) if index in attached_indexes]
    # Branch order was never shuffled; attached_indexes still binds to the
    # generated limb/fruit pair, while the public fruit draw order is shuffled.
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": STAGE,
        "view_limit_deg": VIEW_LIMIT,
        "apples": copy.deepcopy(apples),
        "branches": copy.deepcopy(branches),
        "basket": basket,
        "attached_ids": attached_ids,
        "requirements": requirements,
        "variant_count": VARIANT_COUNT,
    }
    by_id = {apple["id"]: apple for apple in apples}
    for branch in branches:
        fruit = by_id[branch["fruit_id"]]
        head = _project([fruit["position"][0], fruit["position"][1] - 28, fruit["position"][2]], 0)
        tip = _project(branch["points"][-1], 0)
        assert abs(head[0] - tip[0]) < 0.01 and abs(head[1] - tip[1]) < 0.01
    assert len(attached_ids) == 3
    return public_state, ground_truth
