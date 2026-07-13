from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "impossible_panorama"
WORLD_WIDTH = 4800
WORLD_HEIGHT = 2400
VIEW_WIDTH = 820
VIEW_HEIGHT = 450
OBJECT_COUNT = 32
VARIANT_COUNT = 18 * 10_000_000_000_000
PALETTES = ("night-survey", "oxide-dusk", "polar-archive", "violet-hour")


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _round(value: float) -> float:
    return round(float(value), 2)


def _target_contract(challenge_id: str, objects: list[dict[str, Any]], camera: dict[str, Any]) -> dict[str, Any]:
    cx, cy = float(camera["x"]), float(camera["y"])
    far_indices = [
        index
        for index, item in enumerate(objects)
        if abs(float(item["x"]) - cx) > 1080 or abs(float(item["y"]) - cy) > 670
    ]
    if not far_indices:
        raise RuntimeError("panorama has no off-screen event candidate")
    target_index = far_indices[int(challenge_id[:6], 16) % len(far_indices)]
    period_ms = 5880 + (int(challenge_id[6:8], 16) % 7) * 140
    window_ms = 1980
    offset_ms = int(challenge_id[8:12], 16) % period_ms
    return {
        "target_index": target_index,
        "target_id": objects[target_index]["id"],
        "period_ms": period_ms,
        "window_ms": window_ms,
        "offset_ms": offset_ms,
    }


def _make_objects(seed: str, rng: random.Random) -> list[dict[str, Any]]:
    cells = [(column, row) for row in range(4) for column in range(8)]
    rng.shuffle(cells)
    objects: list[dict[str, Any]] = []
    for index, (column, row) in enumerate(cells):
        token = hashlib.sha256(f"{seed}|survey-moth|{index}".encode("utf-8")).hexdigest()[:7]
        objects.append({
            "id": f"specimen-{token}",
            "x": _round(max(270, min(4530, 300 + column * 600 + rng.uniform(-135, 135)))),
            "y": _round(max(160, min(2240, 285 + row * 610 + rng.uniform(-128, 128)))),
            "depth": rng.randint(19, 81),
            "motion_period_ms": rng.randrange(3400, 5101, 100),
            "motion_phase": round(rng.random(), 5),
            "amp_x": rng.randint(7, 16),
            "amp_y": rng.randint(6, 14),
            "vane_span": rng.randint(11, 16),
            "tone": rng.randrange(4),
            "flare_phase": round(rng.random(), 5),
        })
    return objects


def _make_landmarks(rng: random.Random) -> list[dict[str, Any]]:
    kinds = ("mesa", "spire", "dish", "arch", "reed", "relay")
    return [
        {
            "kind": rng.choice(kinds),
            "x": _round(rng.uniform(60, WORLD_WIDTH - 60)),
            "y": _round(rng.uniform(80, WORLD_HEIGHT - 60)),
            "size": rng.randint(24, 78),
            "tone": rng.randrange(5),
            "depth": rng.randint(10, 92),
        }
        for _ in range(108)
    ]


def _make_routes(rng: random.Random) -> list[dict[str, Any]]:
    routes = []
    for _ in range(28):
        x1, y1 = rng.uniform(0, WORLD_WIDTH), rng.uniform(0, WORLD_HEIGHT)
        x2 = max(0, min(WORLD_WIDTH, x1 + rng.uniform(-820, 820)))
        y2 = max(0, min(WORLD_HEIGHT, y1 + rng.uniform(-430, 430)))
        routes.append({
            "x1": _round(x1), "y1": _round(y1), "x2": _round(x2), "y2": _round(y2),
            "bend": _round(rng.uniform(-180, 180)), "tone": rng.randrange(4),
        })
    return routes


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "impossible_panorama_seed_0001@0.1")
    camera = {"x": 2400.0, "y": 1200.0, "zoom": 0.60, "focus": 50.0}
    objects = _make_objects(seed, rng)
    contract = _target_contract(challenge_id, objects, camera)
    target = objects[int(contract["target_index"])]
    search_waypoints = [
        {"x": 700.0, "y": 450.0},
        {"x": 2400.0, "y": 450.0},
        {"x": 4100.0, "y": 450.0},
        {"x": 4100.0, "y": 1950.0},
        {"x": 2400.0, "y": 1950.0},
        {"x": 700.0, "y": 1950.0},
    ]
    controls = {
        "zoom_min": 0.50,
        "zoom_max": 2.40,
        "zoom_step": 0.10,
        "pan_nudge_px": 130,
        "focus_min": 0,
        "focus_max": 100,
        "focus_step": 1,
    }
    qualification = {
        "minimum_zoom": 1.65,
        "maximum_zoom": 2.25,
        "focus_tolerance": 5.0,
        "reticle_radius": 38.0,
        "minimum_hold_ms": 940,
        "minimum_hold_samples": 8,
        "maximum_sample_gap_ms": 155,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt": task.get("natural_language") or "Find the survey moth whose twin vanes lock tip-to-tip inside two expanding rings. Frame it, focus it, and hold the shutter through the event.",
        "generator": {"name": "procedural_impossible_panorama_v1", "variant_count": VARIANT_COUNT},
        "plate_number": f"PAN-{challenge_id[:4].upper()}-{rng.randint(100, 999)}",
        "palette": rng.choice(PALETTES),
        "world": {"width": WORLD_WIDTH, "height": WORLD_HEIGHT, "sector_columns": 8, "sector_rows": 4},
        "viewport": {"width": VIEW_WIDTH, "height": VIEW_HEIGHT},
        "initial_camera": camera,
        "controls": controls,
        "objects": objects,
        "landmarks": _make_landmarks(rng),
        "routes": _make_routes(rng),
        "qualification": qualification,
        "event_vocabulary": "twin vanes lock tip-to-tip inside two expanding cyan rings",
        "submit_label": "DEVELOP PLATE",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "world": public_state["world"],
        "viewport": public_state["viewport"],
        "initial_camera": camera,
        "controls": controls,
        "objects": objects,
        "target_id": contract["target_id"],
        "event_contract": {
            "period_ms": contract["period_ms"],
            "window_ms": contract["window_ms"],
            "offset_ms": contract["offset_ms"],
        },
        "qualification": qualification,
        "solution": {
            "search_waypoints": search_waypoints,
            "target_base": {"x": target["x"], "y": target["y"]},
            "target_depth": target["depth"],
            "zoom": 1.80,
            "event_period_ms": contract["period_ms"],
            "event_window_ms": contract["window_ms"],
            "event_offset_ms": contract["offset_ms"],
        },
        "variant_count": VARIANT_COUNT,
    }
    # Generation-time fairness invariants: the requested specimen starts outside
    # the viewport and its full motion envelope remains inside the world.
    half_width = VIEW_WIDTH / (2 * float(camera["zoom"]))
    half_height = VIEW_HEIGHT / (2 * float(camera["zoom"]))
    assert abs(float(target["x"]) - float(camera["x"])) > half_width or abs(float(target["y"]) - float(camera["y"])) > half_height
    assert float(target["amp_x"]) + 30 < float(target["x"]) < WORLD_WIDTH - float(target["amp_x"]) - 30
    assert float(target["amp_y"]) + 30 < float(target["y"]) < WORLD_HEIGHT - float(target["amp_y"]) - 30
    assert 15 <= float(target["depth"]) <= 85
    assert contract["window_ms"] >= qualification["minimum_hold_ms"] + 700
    return public_state, ground_truth


def target_position(item: dict[str, Any], time_ms: float) -> tuple[float, float]:
    """Shared only for offline audits; the grader duplicates this geometry."""
    angle = (time_ms / float(item["motion_period_ms"]) + float(item["motion_phase"])) * math.tau
    return (
        float(item["x"]) + math.cos(angle) * float(item["amp_x"]),
        float(item["y"]) + math.sin(angle * 1.17) * float(item["amp_y"]),
    )
