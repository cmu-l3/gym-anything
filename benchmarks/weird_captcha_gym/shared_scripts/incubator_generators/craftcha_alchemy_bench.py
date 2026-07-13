from __future__ import annotations

import hashlib
import json
import random
from typing import Any


MECHANIC_ID = "craftcha_alchemy_bench"
VARIANT_COUNT = 9_600_000_000
PROCESS_STATIONS = ("grind", "heat", "infuse", "press")
ALL_STATIONS = (*PROCESS_STATIONS, "assemble")
BRANCH_PATTERNS = ((2, 2, 1), (2, 2, 2), (3, 2, 2), (3, 3, 2))
RAW_MATERIALS = (
    ("copper_bloom", "Copper Bloom", "✿", "#c66b43"),
    ("moon_salt", "Moon Salt", "◇", "#94b9c5"),
    ("amber_resin", "Amber Resin", "⬢", "#d69a37"),
    ("iron_moss", "Iron Moss", "♣", "#678b67"),
    ("glass_seed", "Glass Seed", "◈", "#77a9ad"),
    ("thunder_clay", "Thunder Clay", "ϟ", "#8b779f"),
    ("pearl_ash", "Pearl Ash", "○", "#c4bda8"),
    ("sun_wire", "Sun Wire", "⌁", "#d2ae4f"),
    ("violet_ore", "Violet Ore", "◆", "#8d678c"),
)
DEVICES = (
    ("orrey_key", "ORRERY KEY", "⌾"),
    ("weather_heart", "WEATHER HEART", "☼"),
    ("echo_compass", "ECHO COMPASS", "✣"),
    ("night_engine", "NIGHT ENGINE", "◐"),
    ("tide_lantern", "TIDE LANTERN", "◒"),
    ("memory_latch", "MEMORY LATCH", "⌘"),
    ("hush_motor", "HUSH MOTOR", "⊚"),
)
PALETTES = (
    ("oxide", "#f0ba54", "#4a6f68"),
    ("cinnabar", "#e99556", "#607e93"),
    ("verdigris", "#d7b45b", "#3f877b"),
    ("inkstone", "#e6b968", "#6d718d"),
)
STAGE_WORDS = {
    "grind": ("Milled", "Powdered", "Faceted"),
    "heat": ("Calcined", "Tempered", "Fired"),
    "infuse": ("Attuned", "Charged", "Steeped"),
    "press": ("Stamped", "Laminated", "Crimped"),
}


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _rect(x1: int, y1: int, x2: int, y2: int) -> dict[str, int]:
    return {"x1": x1, "y1": y1, "x2": x2, "y2": y2}


def _geometry() -> dict[str, Any]:
    station_rects = {
        "grind": _rect(346, 105, 518, 304),
        "heat": _rect(530, 105, 702, 304),
        "infuse": _rect(714, 105, 886, 304),
        "press": _rect(440, 326, 612, 525),
        "assemble": _rect(624, 326, 896, 525),
    }
    cycle_rects = {
        station: _rect(rect["x1"] + 18, rect["y2"] - 42, rect["x2"] - 18, rect["y2"] - 10)
        for station, rect in station_rects.items()
    }
    return {
        "width": 1200,
        "height": 690,
        "inventory_slots": [
            _rect(30, 174, 164, 257),
            _rect(174, 174, 308, 257),
            _rect(30, 270, 164, 353),
            _rect(174, 270, 308, 353),
        ],
        "stations": station_rects,
        "cycle_buttons": cycle_rects,
        "delivery": _rect(922, 107, 1182, 526),
        "replay_button": _rect(42, 449, 298, 493),
        "reset_button": _rect(0, 628, 182, 690),
        "verify_button": _rect(982, 636, 1150, 682),
    }


def _recipe_hash(recipe: dict[str, Any]) -> str:
    body = json.dumps(recipe, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]


def _station_sequence(rng: random.Random, stations: list[str], count: int) -> list[str]:
    sequence = list(stations)
    rng.shuffle(sequence)
    while len(sequence) < count:
        choices = [station for station in stations if station != sequence[-1]]
        counts = {station: sequence.count(station) for station in choices}
        minimum = min(counts.values())
        least_used = [station for station in choices if counts[station] == minimum]
        sequence.append(rng.choice(least_used))
    return sequence[:count]


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "craftcha_alchemy_bench_seed_0001@0.1")
    chosen_materials = rng.sample(list(RAW_MATERIALS), 3)
    device_id, device_name, device_symbol = rng.choice(DEVICES)
    branch_lengths = rng.choice(BRANCH_PATTERNS)
    chosen_process_stations = rng.sample(list(PROCESS_STATIONS), 3)
    total_processes = sum(branch_lengths)
    station_sequence = _station_sequence(rng, chosen_process_stations, total_processes)
    palette_name, accent, reagent_accent = rng.choice(PALETTES)

    branches: list[dict[str, Any]] = []
    solution_steps: list[dict[str, Any]] = []
    cursor = 0
    global_step = 0
    for branch_index, (material, branch_length) in enumerate(zip(chosen_materials, branch_lengths)):
        base_id, raw_name, symbol, color = material
        branch_id = chr(65 + branch_index)
        raw_state_id = f"{challenge_id}:{base_id}:0"
        current_state = raw_state_id
        steps: list[dict[str, Any]] = []
        station_counts: dict[str, int] = {}
        for local_index in range(branch_length):
            station = station_sequence[cursor]
            cursor += 1
            global_step += 1
            station_counts[station] = station_counts.get(station, 0) + 1
            word_options = STAGE_WORDS[station]
            word = word_options[(branch_index + local_index + rng.randrange(len(word_options))) % len(word_options)]
            suffix = f" {station_counts[station]}" if station_counts[station] > 1 else ""
            output_state = f"{challenge_id}:{base_id}:{local_index + 1}:{station}"
            output_name = f"{word} {raw_name}{suffix}"
            step = {
                "step": global_step,
                "branch_id": branch_id,
                "station_id": station,
                "input_state_id": current_state,
                "output_state_id": output_state,
                "output_name": output_name,
            }
            steps.append(step)
            solution_steps.append(dict(step))
            current_state = output_state
        branches.append({
            "branch_id": branch_id,
            "base_id": base_id,
            "raw_state_id": raw_state_id,
            "raw_name": raw_name,
            "symbol": symbol,
            "color": color,
            "steps": steps,
            "terminal_state_id": current_state,
            "terminal_name": steps[-1]["output_name"],
        })

    global_step += 1
    device_state_id = f"{challenge_id}:device:{device_id}"
    assemble_step = {
        "step": global_step,
        "branch_id": "FINAL",
        "station_id": "assemble",
        "input_state_ids": [branch["terminal_state_id"] for branch in branches],
        "output_state_id": device_state_id,
        "output_name": device_name,
    }
    solution_steps.append(dict(assemble_step))
    recipe = {
        "recipe_code": f"R-{challenge_id[:4].upper()}-{rng.randint(100, 999)}",
        "device_id": device_id,
        "device_state_id": device_state_id,
        "device_name": device_name,
        "device_symbol": device_symbol,
        "branches": branches,
        "assemble_step": assemble_step,
        "step_count": global_step,
    }
    recipe_hash = _recipe_hash(recipe)
    geometry = _geometry()
    station_serials = {
        station: f"{station[:2].upper()}-{rng.randint(120, 989)}"
        for station in ALL_STATIONS
    }
    initial_window_ms = 5500 + 300 * rng.randrange(5)
    replay_window_ms = 3500 + 300 * rng.randrange(4)
    initial_inventory = [branch["raw_state_id"] for branch in branches] + [None]
    active_station_ids = sorted({step["station_id"] for step in solution_steps})

    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt": task.get("natural_language") or "Study the recipe, craft its intermediates, assemble the device, and deliver it.",
        "generator": {"name": "transient_lineage_alchemy_v1", "variant_count": VARIANT_COUNT},
        "bench_serial": f"AL-{challenge_id[:6].upper()}",
        "palette": {"name": palette_name, "accent": accent, "reagent": reagent_accent},
        "geometry": geometry,
        "recipe": recipe,
        "recipe_hash": recipe_hash,
        "recipe_window_ms": initial_window_ms,
        "replay_window_ms": replay_window_ms,
        "memory_charge_initial": 3,
        "memory_replay_cost": 2,
        "replay_limit": 1,
        "inventory_capacity": 4,
        "initial_inventory": initial_inventory,
        "active_station_ids": active_station_ids,
        "station_serials": station_serials,
        "submit_label": "CERTIFY DEVICE",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "geometry": geometry,
        "recipe": recipe,
        "recipe_hash": recipe_hash,
        "recipe_window_ms": initial_window_ms,
        "replay_window_ms": replay_window_ms,
        "memory_charge_initial": 3,
        "memory_replay_cost": 2,
        "replay_limit": 1,
        "inventory_capacity": 4,
        "initial_inventory": initial_inventory,
        "active_station_ids": active_station_ids,
        "station_serials": station_serials,
        "solution_steps": solution_steps,
        "variant_count": VARIANT_COUNT,
    }

    assert 6 <= recipe["step_count"] <= 9
    assert len(initial_inventory) == 4 and initial_inventory.count(None) == 1
    assert len(active_station_ids) == 4 and "assemble" in active_station_ids
    assert set(assemble_step["input_state_ids"]) == {branch["terminal_state_id"] for branch in branches}
    assert [step["step"] for step in solution_steps] == list(range(1, recipe["step_count"] + 1))
    return public_state, ground_truth
