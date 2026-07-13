from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "wrong_number"
PHASE_STEPS = 32
SKEW_MIN = -6
SKEW_MAX = 6
LINE_COUNT = 7
TONES = ("mint", "amber", "violet", "coral", "ice", "lime", "rose")


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _line_id(seed: str, slot: int) -> str:
    digest = hashlib.sha256(f"{seed}|carrier|{slot}".encode("utf-8")).hexdigest()[:9]
    return f"line-{slot + 1}-{digest}"


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    target_slot = rng.randrange(LINE_COUNT)
    tones = list(TONES)
    rng.shuffle(tones)
    lines: list[dict[str, Any]] = []
    for slot in range(LINE_COUNT):
        phase_offset = rng.randrange(PHASE_STEPS)
        skew_offset = rng.randint(-5, 5)
        drift_milli = rng.choice((-1680, -1510, -1340, -1180, 1180, 1340, 1510, 1680))
        distortion_milli = 0 if slot == target_slot else rng.randint(1380, 2120)
        lines.append(
            {
                "id": _line_id(seed, slot),
                "slot": slot,
                "tone": tones[slot],
                "phase_offset_steps": phase_offset,
                "skew_offset_steps": skew_offset,
                "drift_milli_steps_per_second": drift_milli,
                "distortion_milli": distortion_milli,
                "waveform_seed": rng.randrange(1_000, 9_999),
            }
        )

    target = lines[target_slot]
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "wrong_number_seed_0001@0.1")
    qualification = {
        "phase_steps": PHASE_STEPS,
        "phase_tolerance_milli_steps": 1150,
        "skew_min": SKEW_MIN,
        "skew_max": SKEW_MAX,
        "skew_tolerance_milli_steps": 720,
        "trial_ms": 4_800,
        "sample_ms": 120,
        "minimum_lock_samples": 30,
        "final_window_samples": 10,
        "minimum_final_lock_samples": 7,
        "maximum_sample_gap_ms": 175,
    }
    waveform = {
        "base_harmonic_milli": rng.randint(280, 380),
        "reference_twist_milli_radians": rng.randint(220, 520),
        "distortion_gain_milli": 115,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Phase-lock the authorized carrier. The impostor lines never hold sync.",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "generator": {"name": "wrong_number_active_tracking_v3", "variant_count": 64_800_000_000},
        "lines": lines,
        "qualification": qualification,
        "waveform": waveform,
        "submit_label": "TEST THIS LINE",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "lines": lines,
        "qualification": qualification,
        "waveform": waveform,
        "target_line_id": target["id"],
        "target_slot": target_slot,
        "solution_phase_step": (-int(target["phase_offset_steps"])) % PHASE_STEPS,
        "solution_skew_step": -int(target["skew_offset_steps"]),
        "variant_count": 64_800_000_000,
    }
    assert len(lines) == LINE_COUNT
    assert len({line["id"] for line in lines}) == LINE_COUNT
    assert sum(int(line["distortion_milli"]) == 0 for line in lines) == 1
    assert SKEW_MIN <= int(ground_truth["solution_skew_step"]) <= SKEW_MAX
    return public_state, ground_truth
