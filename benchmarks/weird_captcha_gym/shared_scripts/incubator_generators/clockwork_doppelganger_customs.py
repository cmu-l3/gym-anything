from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "clockwork_doppelganger_customs"
PALETTES = ("timecard-amber", "customs-blue", "oxide-green", "carbon-red")
VARIANT_COUNT = 3 * 3 * 4 * 10_000_000_000


def _seed_int(seed: str, salt: str) -> int:
    return int(hashlib.sha256(f"{seed}|{salt}".encode()).hexdigest()[:16], 16)


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:12]
    task_id = str(task.get("id") or "clockwork_doppelganger_customs_seed_0001@0.1")
    loop_ms = rng.choice((5900, 6100, 6300))
    record_ms = 2300
    track_y = rng.choice((250, 270, 290))
    catch_time = rng.choice((750, 800, 850))
    speed = rng.choice((0.205, 0.215, 0.225))
    start_x = 72
    pickup = {"x": round(start_x + speed * catch_time, 2), "y": track_y}
    vertical = rng.choice((-1, 1))
    handoff_a = {"x": 348 + rng.randint(-12, 12), "y": track_y + vertical * 82}
    stamp = {"x": 505 + rng.randint(-10, 10), "y": track_y - vertical * 58}
    handoff_b = {"x": 642 + rng.randint(-12, 12), "y": track_y + vertical * 72}
    exit_point = {"x": 790, "y": track_y}
    stations = {"pickup": pickup, "handoff_a": handoff_a, "stamp": stamp, "handoff_b": handoff_b, "exit": exit_point}
    conveyor = {"start_x": start_x, "track_y": track_y, "speed_px_per_ms": speed, "catch_time_ms": catch_time}
    controls = {"record_duration_ms": record_ms, "loop_duration_ms": loop_ms, "phase_step_ms": 50, "sample_interval_ms": 80, "cycle_sample_interval_ms": 100}
    qualification = {
        "minimum_record_samples": 24, "maximum_record_sample_gap_ms": 240, "maximum_pointer_step_px": 98,
        "minimum_path_travel_px": 90, "action_path_tolerance_px": 48, "grab_radius_px": 38,
        "station_radius_px": 42, "handoff_window_ms": 230, "minimum_cycle_samples": 45,
        "maximum_cycle_sample_gap_ms": 260,
    }
    roles = [
        {"slot": 0, "title": "CATCH / PASS A", "required_actions": ["grab", "release"], "guide": [pickup, handoff_a]},
        {"slot": 1, "title": "STAMP / PASS B", "required_actions": ["grab", "stamp", "release"], "guide": [handoff_a, stamp, handoff_b]},
        {"slot": 2, "title": "DELIVER / RELEASE", "required_actions": ["grab", "release"], "guide": [handoff_b, exit_point]},
    ]
    nominal = [
        {"grab": 350, "release": 1750},
        {"grab": 350, "stamp": 1050, "release": 1850},
        {"grab": 350, "release": 1650},
    ]
    phase_a = catch_time - nominal[0]["grab"]
    release_a = phase_a + nominal[0]["release"]
    phase_b = release_a + 100 - nominal[1]["grab"]
    release_b = phase_b + nominal[1]["release"]
    phase_c = release_b + 100 - nominal[2]["grab"]
    phases = [int(round(value / 50) * 50) for value in (phase_a, phase_b, phase_c)]
    assert phases[2] + nominal[2]["release"] < loop_ms - 150
    for role in roles:
        guide_length = sum(math.hypot(float(after["x"]) - float(before["x"]), float(after["y"]) - float(before["y"])) for before, after in zip(role["guide"], role["guide"][1:]))
        assert guide_length >= qualification["minimum_path_travel_px"] + 15
    public_state = {
        "benchmark": "weird_captcha_gym", "mechanic_id": MECHANIC_ID, "task_id": task_id,
        "challenge_id": challenge_id, "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt": task.get("natural_language") or "Record three short operator loops, phase them together, and pass one passport through catch, stamp, and delivery.",
        "generator": {"name": "concurrent_recorded_ghost_customs_v1", "variant_count": VARIANT_COUNT},
        "desk_id": f"CLK-{challenge_id[:4].upper()}-{rng.randint(100,999)}", "palette": rng.choice(PALETTES),
        "canvas": {"width": 860, "height": 420}, "stations": stations, "conveyor": conveyor,
        "roles": roles, "controls": controls, "qualification": qualification, "submit_label": "FILE CUSTOMS LOG",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID, "task_id": task_id, "seed": seed, "challenge_id": challenge_id,
        "canvas": public_state["canvas"], "stations": stations, "conveyor": conveyor, "roles": roles,
        "controls": controls, "qualification": qualification,
        "solution": {"nominal_action_times": nominal, "phases_ms": phases, "handoff_gap_ms": 100},
        "variant_count": VARIANT_COUNT,
    }
    return public_state, ground_truth
