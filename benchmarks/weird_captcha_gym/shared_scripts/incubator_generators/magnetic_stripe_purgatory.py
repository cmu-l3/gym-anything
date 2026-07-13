from __future__ import annotations

import copy
import hashlib
import random
from typing import Any


MECHANIC_ID = "magnetic_stripe_purgatory"
STAGE_WIDTH = 1000
STAGE_HEIGHT = 430
VARIANT_COUNT = 18_662_400_000

PALETTES = (
    {"name": "municipal_aqua", "desk": "#c9c5b4", "ink": "#192f3b", "signal": "#46d5dd", "warning": "#e86650", "card": "#e7e0c8"},
    {"name": "night_shift_amber", "desk": "#b9ad97", "ink": "#302b29", "signal": "#f4c767", "warning": "#cc5348", "card": "#eee3ca"},
    {"name": "violet_terminal", "desk": "#c7bcc8", "ink": "#31283e", "signal": "#79d7c5", "warning": "#e65f78", "card": "#eee3df"},
    {"name": "olive_bureau", "desk": "#bfc2a8", "ink": "#29372f", "signal": "#a8dc69", "warning": "#d7614d", "card": "#e9e3c9"},
)

BADGES = (
    {"code": "TRI", "symbol": "▲", "color": "#e36b55"},
    {"code": "ORB", "symbol": "●", "color": "#48bcca"},
    {"code": "BAR", "symbol": "▰", "color": "#d1aa43"},
)

PROFILES = (
    {"token": "quartz", "minimum_ms": 440, "maximum_ms": 700, "solver_ms": 565, "straightness_px": 15},
    {"token": "pendulum", "minimum_ms": 700, "maximum_ms": 1050, "solver_ms": 865, "straightness_px": 17},
    {"token": "glacier", "minimum_ms": 1050, "maximum_ms": 1420, "solver_ms": 1220, "straightness_px": 19},
)


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def _entity_id(seed: str, kind: str, index: int) -> str:
    token = hashlib.sha256(f"{seed}|{kind}|{index}".encode("utf-8")).hexdigest()[:8]
    return f"{kind}-{token}"


def _reader_geometry(index: int, direction: str, rng: random.Random) -> dict[str, Any]:
    top = 8 + index * 138
    center_y = top + 72
    zones: list[dict[str, Any]] = []
    zone_xs = rng.sample(range(510, 825, 35), 2)
    for zone_index, x in enumerate(sorted(zone_xs)):
        above = (zone_index + index + rng.randrange(2)) % 2 == 0
        zones.append(
            {
                "id": f"static-{index + 1}-{zone_index + 1}",
                "x": x,
                "y": center_y - 45 if above else center_y + 24,
                "width": rng.randint(46, 66),
                "height": rng.randint(15, 19),
            }
        )
    return {
        "rect": {"x": 214, "y": top, "width": 770, "height": 128},
        "slot": {"x": 232, "y": top + 25, "width": 150, "height": 78},
        "track": {
            "x_start": 430,
            "x_end": 942,
            "y": center_y,
            "lane_half_height": 20,
            "direction": direction,
        },
        "interference_zones": zones,
    }


def _public_reader(reader: dict[str, Any]) -> dict[str, Any]:
    return {
        key: copy.deepcopy(reader[key])
        for key in ("id", "label", "serial", "badge", "rect", "slot", "track", "interference_zones", "profile_token")
    }


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    task_id = str(task.get("id") or "magnetic_stripe_purgatory_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|calibration-v1".encode("utf-8")).hexdigest()[:14]
    palette = copy.deepcopy(rng.choice(PALETTES))

    directions = [rng.choice(("ltr", "rtl")) for _ in range(3)]
    if len(set(directions)) == 1:
        directions[rng.randrange(3)] = "rtl" if directions[0] == "ltr" else "ltr"
    profiles = [copy.deepcopy(item) for item in PROFILES]
    rng.shuffle(profiles)
    badges = [copy.deepcopy(item) for item in BADGES]
    rng.shuffle(badges)

    readers: list[dict[str, Any]] = []
    for index in range(3):
        geometry = _reader_geometry(index, directions[index], rng)
        reader = {
            "id": _entity_id(seed, "reader", index),
            "label": f"READER {index + 1}",
            "serial": f"R-{rng.randint(100, 999)}-{chr(65 + index)}",
            "badge": badges[index],
            **geometry,
            "profile_token": profiles[index]["token"],
            "calibration": {
                "minimum_ms": profiles[index]["minimum_ms"],
                "maximum_ms": profiles[index]["maximum_ms"],
                "solver_ms": profiles[index]["solver_ms"],
                "straightness_px": profiles[index]["straightness_px"],
                "maximum_backtrack_px": 18,
                "minimum_samples": 14,
                "minimum_coverage_milli": 920,
                "maximum_sample_gap_px": 58,
            },
        }
        readers.append(reader)

    # Card rack order is independent from reader order. Matching badge and
    # colour are the visible assignment; the direct reader id remains hidden.
    assignments = list(range(3))
    rng.shuffle(assignments)
    cards: list[dict[str, Any]] = []
    for rack_index, reader_index in enumerate(assignments):
        reader = readers[reader_index]
        cards.append(
            {
                "id": _entity_id(seed, "card", rack_index),
                "label": f"CARD {chr(65 + rack_index)}",
                "account": f"{rng.randint(1000, 9999)} {rng.randint(1000, 9999)}",
                "holder": rng.choice(("M. STATIC", "A. RETRY", "J. CALIBRATE", "T. STRIPE")),
                "badge": copy.deepcopy(reader["badge"]),
                "initial_rect": {"x": 24, "y": 28 + rack_index * 132, "width": 158, "height": 82},
                "assigned_reader": str(reader["id"]),
            }
        )

    public_cards = [{key: copy.deepcopy(card[key]) for key in ("id", "label", "account", "holder", "badge", "initial_rect")} for card in cards]
    requirements = {
        "card_count": 3,
        "minimum_insert_moves": 4,
        "minimum_insert_ms": 90,
        "minimum_swipe_samples": 14,
        "attempt_limit": 0,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": "Match each card to its badge reader. Learn each reader's temperament by swiping until all three lock.",
        "submit_label": "RUN CALIBRATION AUDIT",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {
            "name": "multi_reader_card_calibration_desk_v1",
            "variant_count": VARIANT_COUNT,
            "variant_count_kind": "palette/card-order/assignment/direction/window/interference construction space",
        },
        "palette": palette,
        "stage": {"width": STAGE_WIDTH, "height": STAGE_HEIGHT},
        "cards": public_cards,
        "readers": [_public_reader(reader) for reader in readers],
        "requirements": requirements,
        "rules": [
            "Match each card badge to the reader carrying the same badge, then physically drag the card into its insertion slot.",
            "Swipe from the illuminated arrow end to the opposite end with a dense, straight, monotonic pointer path.",
            "Every reader has a different hidden timing temperament. Use TOO FAST, TOO SLOW, and BAD READ feedback; retries are unlimited.",
            "Accepted readers lock. Audit only after all three indicator lamps are accepted.",
        ],
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "palette": palette,
        "stage": public_state["stage"],
        "cards": copy.deepcopy(cards),
        "readers": copy.deepcopy(readers),
        "requirements": requirements,
        "variant_count": VARIANT_COUNT,
        "variant_count_kind": public_state["generator"]["variant_count_kind"],
    }
    assert len({reader["calibration"]["solver_ms"] for reader in readers}) == 3
    assert len({card["assigned_reader"] for card in cards}) == 3
    assert all(reader["calibration"]["minimum_ms"] < reader["calibration"]["solver_ms"] < reader["calibration"]["maximum_ms"] for reader in readers)
    return public_state, ground_truth
