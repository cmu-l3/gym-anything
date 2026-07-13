from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "crash_deadline_hovercar"
STAGE = {"width": 980, "height": 480}


def _seed_int(seed: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).digest()[:8], "big")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed))
    phase = round(rng.uniform(-1.5, 1.5), 6)
    amplitude = rng.randint(38, 52)
    period = rng.randint(165, 195)
    hues = rng.sample(["#b8ff58", "#60e6ff", "#ffcb66", "#ff7699", "#b995ff", "#77f2b3"], 5)
    motifs = rng.sample(("ring-notch", "split-kite", "triple-fin", "hollow-cross", "offset-orbit"), 5)
    targets = []
    windows = ((18, 62), (59, 107), (104, 152), (149, 198), (195, 248))
    for index, (start, end) in enumerate(windows):
        targets.append({
            "id": f"check-{index + 1}", "motif": motifs[index], "color": hues[index],
            "window_start": start, "window_end": end, "base_x": (650, 795, 870, 690, 835)[index],
            "base_y": (92, 175, 82, 360, 315)[index], "orbit_x": rng.randint(34, 54), "orbit_y": rng.randint(22, 36),
            "phase": round(rng.uniform(0, math.tau), 6), "radius": 29,
            "required_ticks": rng.choice((11, 12, 13)),
        })
    obstacles = [
        {"id": "barrier-a", "world_x": 280, "lane_offset": -28, "width": 48, "height": 34},
        {"id": "barrier-b", "world_x": 500, "lane_offset": 30, "width": 52, "height": 34},
        {"id": "barrier-c", "world_x": 720, "lane_offset": -30, "width": 46, "height": 36},
        {"id": "barrier-d", "world_x": 930, "lane_offset": 27, "width": 54, "height": 32},
        {"id": "barrier-e", "world_x": 1140, "lane_offset": -29, "width": 48, "height": 36},
        {"id": "barrier-f", "world_x": 1320, "lane_offset": 28, "width": 50, "height": 34},
    ]
    task_id = str(task.get("id") or "crash_deadline_hovercar_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:12]
    physics = {
        "tick_ms": 50, "start_speed": 30.0, "min_speed": 18.0, "max_speed": 86.0,
        "acceleration": 3.4, "brake": 6.0, "drag": 0.72,
        "steer_gain": 2.35, "lateral_damping": 0.84,
        "road_half_width": 110, "car_half_width": 24, "car_half_height": 14,
        "finish_progress": 1400, "deadline_tick": 330,
        "road_amplitude": amplitude, "road_period": period, "road_phase": phase,
    }
    full_throttle_speed = physics["start_speed"]
    full_throttle_progress = 0.0
    earliest_finish = 0
    while full_throttle_progress < physics["finish_progress"]:
        earliest_finish += 1
        full_throttle_speed = min(physics["max_speed"], full_throttle_speed + physics["acceleration"] - physics["drag"])
        full_throttle_progress += full_throttle_speed / 10
    public = {
        "benchmark": "weird_captcha_gym", "mechanic_id": MECHANIC_ID, "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Complete each hover check while keeping the vehicle from crashing.",
        "submit_label": "TRANSMIT FLIGHT RECORD", "stage": STAGE, "physics": physics,
        "targets": targets, "obstacles": obstacles,
        "generator": {"name": "fixed_step_divided_attention_course_v2", "variant_count": 88_400_000_000},
        "requirements": {"check_count": len(targets), "minimum_motion_during_dwell": 1.5},
        "clearance_audit": {"road_margin": 56, "target_window_slack_ticks": 25, "obstacle_bypass_margin": 24,
                            "full_throttle_finish_tick": earliest_finish, "final_window_start": windows[-1][0]},
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
    }
    truth = {**public, "seed": seed}
    assert all(item["window_end"] - item["window_start"] >= item["required_ticks"] + 30 for item in targets)
    assert physics["finish_progress"] > max(item["world_x"] for item in obstacles)
    assert earliest_finish < windows[-1][0], "full throttle must force a braking/coast tradeoff before the final inspection"
    return public, truth
