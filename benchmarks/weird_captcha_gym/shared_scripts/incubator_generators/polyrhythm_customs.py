from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "polyrhythm_customs"
LANES = (
    {"id": "lane-a", "key": "A", "label": "AMBER", "glyph": "◆"},
    {"id": "lane-s", "key": "S", "label": "SIGNAL", "glyph": "●"},
    {"id": "lane-d", "key": "D", "label": "DOCK", "glyph": "▰"},
)


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    beat_ms = rng.choice((420, 440, 460))
    lead_ms = rng.choice((360, 400, 440))
    patterns = [[0, 3, 7], [1, 4, 8], [2, 6, 9]]
    rng.shuffle(patterns)
    chord_slot = rng.choice((5, 6))
    chord_lanes = sorted(rng.sample(range(3), 2))
    hold_lane = rng.randrange(3)

    notes: list[dict[str, Any]] = []
    for lane_index, lane in enumerate(LANES):
        slots = list(patterns[lane_index])
        if lane_index in chord_lanes and chord_slot not in slots:
            slots.append(chord_slot)
        slots.sort()
        first_slot = slots[0]
        for note_index, slot in enumerate(slots):
            is_chord = lane_index in chord_lanes and slot == chord_slot
            jitter = 0 if is_chord else rng.randrange(-28, 29, 4)
            start_ms = lead_ms + slot * beat_ms + jitter
            is_hold = lane_index == hold_lane and slot == first_slot
            duration_ms = rng.randrange(720, 861, 20) if is_hold else rng.randrange(90, 131, 10)
            notes.append(
                {
                    "id": f"note-{lane_index}-{note_index}",
                    "lane": lane["id"],
                    "start_ms": start_ms,
                    "duration_ms": duration_ms,
                    "kind": "hold" if is_hold else "tap",
                    "chord_id": "chord-1" if is_chord else None,
                }
            )
    notes.sort(key=lambda note: (int(note["start_ms"]), str(note["lane"])))
    chord_start = lead_ms + chord_slot * beat_ms
    performance_ms = max(int(note["start_ms"]) + int(note["duration_ms"]) for note in notes) + 480
    preview_order = list(range(3))
    rng.shuffle(preview_order)
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "")
    settings = {
        "performance_ms": performance_ms,
        "preview_scale": 0.56,
        "preview_gap_ms": 360,
        "countdown_ms": 1_650,
        "start_window_ms": 230,
        "duration_tolerance_ms": 320,
        "chord_window_ms": 160,
        "pass_accuracy": 0.85,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Inspect each lane separately. Then perform the combined clearance on A, S, and D.",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "generator": {"name": "polyrhythm_customs_v1", "variant_count": 1_400_000_000},
        "lanes": [dict(lane) for lane in LANES],
        "score": notes,
        "preview_order": preview_order,
        "settings": settings,
        "rules": {
            "start_window_ms": settings["start_window_ms"],
            "duration_tolerance_ms": settings["duration_tolerance_ms"],
            "chord_window_ms": settings["chord_window_ms"],
            "pass_accuracy_percent": 85,
        },
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "lanes": [dict(lane) for lane in LANES],
        "expected_notes": notes,
        "chords": [
            {
                "id": "chord-1",
                "lanes": [LANES[index]["id"] for index in chord_lanes],
                "start_ms": chord_start,
            }
        ],
        "settings": settings,
        "variant_count": 1_400_000_000,
    }
    assert any(note["kind"] == "hold" for note in notes)
    assert sum(1 for note in notes if note.get("chord_id") == "chord-1") == 2
    return public_state, ground_truth
