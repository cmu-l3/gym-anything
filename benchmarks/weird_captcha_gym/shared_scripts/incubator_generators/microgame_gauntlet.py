from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "microgame_gauntlet"
ROUND_TYPES = ("pressure", "chord", "dial", "intercept", "route")
CHORDS = (("A", "L"), ("D", "K"), ("F", "J"), ("Q", "P"), ("S", "K"))
PULSE_POSITIONS = ((22, 32), (50, 23), (77, 36), (32, 69), (66, 72))
ROUTE_TEMPLATES = (
    ((12, 72), (25, 42), (43, 57), (59, 25), (77, 46), (89, 18)),
    ((10, 24), (27, 58), (42, 32), (57, 71), (74, 45), (91, 76)),
    ((12, 50), (28, 20), (45, 66), (61, 37), (76, 73), (90, 42)),
)


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    order = list(ROUND_TYPES)
    rng.shuffle(order)
    pulse_positions = list(PULSE_POSITIONS)
    rng.shuffle(pulse_positions)
    pulse_count = rng.choice((3, 4))
    pulse_ids = [f"P{index + 1}-{rng.randint(20, 98)}" for index in range(pulse_count)]
    chord = rng.choice(CHORDS)
    dial_start = rng.randrange(0, 360, 30)
    dial_target = (dial_start + rng.choice((120, 150, 180, 210, 240))) % 360
    route_template = rng.choice(ROUTE_TEMPLATES)
    route_points = [
        {"x": max(7, min(93, x + rng.randint(-2, 2))), "y": max(12, min(82, y + rng.randint(-2, 2))), "index": index}
        for index, (x, y) in enumerate(route_template)
    ]
    rounds: list[dict[str, Any]] = []
    for sequence, round_type in enumerate(order):
        base: dict[str, Any] = {
            "id": f"R{sequence + 1}-{hashlib.sha256(f'{seed}|{round_type}'.encode()).hexdigest()[:5]}",
            "type": round_type,
            "sequence": sequence,
            "energy_cost": 8,
        }
        if round_type == "pressure":
            base.update({
                "title": "PRESSURE / PULSE BANK",
                "instruction": "Hold SPACE continuously. While held, click the lit pulse sockets in order; release only after the bank is dark.",
                "pulses": [
                    {"id": pulse_ids[index], "x": pulse_positions[index][0], "y": pulse_positions[index][1], "order": index}
                    for index in range(pulse_count)
                ],
            })
        elif round_type == "chord":
            base.update({
                "title": "TWO-KEY MAGNETIC CHORD",
                "instruction": f"Hold {chord[0]} + {chord[1]} together until five charge bars fill, then release both keys.",
                "keys": list(chord),
                "required_ticks": 5,
                "tick_ms": 130,
            })
        elif round_type == "dial":
            base.update({
                "title": "INERTIAL BRAKE DIAL",
                "instruction": "Drag around the flywheel to spin it. Release, let it coast, then brake inside the striped target sector.",
                "start_angle": dial_start,
                "target_angle": dial_target,
                "target_tolerance": 28,
                "friction": 0.92,
                "tick_ms": 110,
            })
        elif round_type == "intercept":
            base.update({
                "title": "MOVING-PACKET INTERCEPT",
                "instruction": "Arm the scanner. Click the moving packet only while its center crosses the illuminated capture gate.",
                "speed": round(rng.uniform(3.8, 5.2), 2),
                "gate_center": rng.randint(43, 57),
                "gate_half_width": 9,
                "tick_ms": 120,
            })
        else:
            base.update({
                "title": "BALANCE-ROUTE COURIER",
                "instruction": "Drag the reactor capsule through every numbered hoop without leaving the visible route corridor.",
                "points": route_points,
                "checkpoint_radius": 8,
                "corridor_radius": 13,
            })
        rounds.append(base)

    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Complete all five reactor trials without exhausting stability.",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "mixed_input_verification_reactor_v1", "variant_count": 8_000_000_000},
        "reactor_id": f"VR-{challenge_id.upper()}",
        "rounds": rounds,
        "starting_energy": 100,
        "fault_penalty": 12,
        "reset_penalty": 4,
        "submit_label": "CERTIFY REACTOR",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "rounds": rounds,
        "round_order": [round_data["id"] for round_data in rounds],
        "starting_energy": 100,
        "fault_penalty": 12,
        "reset_penalty": 4,
        "variant_count": 8_000_000_000,
    }
    assert {round_data["type"] for round_data in rounds} == set(ROUND_TYPES)
    assert len({round_data["id"] for round_data in rounds}) == 5
    return public_state, ground_truth
