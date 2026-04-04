#!/usr/bin/env python3
"""Verifier for periodized_team_training task.

Checks that three periodized training routines were created with correct
descriptions and training days (including day-of-week assignments).

Scoring breakdown (100 points):
  C1  (12 pts): "Phase 1 - Anatomical Adaptation" routine exists with correct description
  C2  (12 pts): "Phase 2 - Maximal Strength" routine exists with correct description
  C3  (12 pts): "Phase 3 - Power Development" routine exists with correct description
  C4  ( 8 pts): Phase 1 has "Upper Body Foundations" day
  C5  ( 8 pts): Phase 1 has "Lower Body Foundations" day
  C6  ( 8 pts): Phase 2 has "Heavy Upper" day
  C7  ( 8 pts): Phase 2 has "Heavy Lower" day
  C8  ( 8 pts): Phase 3 has "Explosive Upper" day
  C9  ( 8 pts): Phase 3 has "Explosive Lower" day
  C10 (16 pts): At least 4 of the 6 days have correct day-of-week assignments

Pass threshold: 70 points
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/periodized_training_result.json"

# Day-of-week mapping: wger uses 1=Monday ... 7=Sunday
DOW_MAP = {
    "Monday": 1,
    "Tuesday": 2,
    "Wednesday": 3,
    "Thursday": 4,
    "Friday": 5,
    "Saturday": 6,
    "Sunday": 7,
}

# Expected structure: (routine_key, day_name, expected_dow_int)
EXPECTED_DAYS = [
    ("phase1", "Upper Body Foundations", DOW_MAP["Monday"]),
    ("phase1", "Lower Body Foundations", DOW_MAP["Thursday"]),
    ("phase2", "Heavy Upper", DOW_MAP["Tuesday"]),
    ("phase2", "Heavy Lower", DOW_MAP["Friday"]),
    ("phase3", "Explosive Upper", DOW_MAP["Monday"]),
    ("phase3", "Explosive Lower", DOW_MAP["Wednesday"]),
]

EXPECTED_DESCRIPTIONS = {
    "phase1": "Weeks 1-4: Movement quality and work capacity foundation",
    "phase2": "Weeks 5-8: Heavy compound lifts for peak force production",
    "phase3": "Weeks 9-12: Explosive movements and sport-specific power",
}

EXPECTED_ROUTINE_NAMES = {
    "phase1": "Phase 1 - Anatomical Adaptation",
    "phase2": "Phase 2 - Maximal Strength",
    "phase3": "Phase 3 - Power Development",
}


def verify_periodized_team_training(traj, env_info, task_info):
    """Verify that all three periodized routines and their days were created."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Read result JSON from the environment
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, "r") as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found in VM. Export may have failed.",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    phase1 = result.get("phase1", {})
    phase2 = result.get("phase2", {})
    phase3 = result.get("phase3", {})
    phases = {"phase1": phase1, "phase2": phase2, "phase3": phase3}

    # ---------------------------------------------------------------
    # Gate: If zero routines from the 3 phases exist, score = 0
    # ---------------------------------------------------------------
    routines_found = sum(1 for p in phases.values() if p.get("found"))
    if routines_found == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: None of the three phase routines were created.",
        }

    # ---------------------------------------------------------------
    # C1 (12 pts): Phase 1 routine exists with correct description
    # ---------------------------------------------------------------
    if phase1.get("found"):
        desc = (phase1.get("description") or "").strip()
        expected_desc = EXPECTED_DESCRIPTIONS["phase1"]
        if expected_desc.lower() in desc.lower() or desc.lower() in expected_desc.lower():
            score += 12
            feedback.append("C1: Phase 1 routine found with correct description (+12)")
        else:
            score += 6
            feedback.append(
                f"C1: Phase 1 routine found but description mismatch (+6). "
                f"Got: '{desc}'"
            )
    else:
        feedback.append("C1: Phase 1 routine not found (+0)")

    # ---------------------------------------------------------------
    # C2 (12 pts): Phase 2 routine exists with correct description
    # ---------------------------------------------------------------
    if phase2.get("found"):
        desc = (phase2.get("description") or "").strip()
        expected_desc = EXPECTED_DESCRIPTIONS["phase2"]
        if expected_desc.lower() in desc.lower() or desc.lower() in expected_desc.lower():
            score += 12
            feedback.append("C2: Phase 2 routine found with correct description (+12)")
        else:
            score += 6
            feedback.append(
                f"C2: Phase 2 routine found but description mismatch (+6). "
                f"Got: '{desc}'"
            )
    else:
        feedback.append("C2: Phase 2 routine not found (+0)")

    # ---------------------------------------------------------------
    # C3 (12 pts): Phase 3 routine exists with correct description
    # ---------------------------------------------------------------
    if phase3.get("found"):
        desc = (phase3.get("description") or "").strip()
        expected_desc = EXPECTED_DESCRIPTIONS["phase3"]
        if expected_desc.lower() in desc.lower() or desc.lower() in expected_desc.lower():
            score += 12
            feedback.append("C3: Phase 3 routine found with correct description (+12)")
        else:
            score += 6
            feedback.append(
                f"C3: Phase 3 routine found but description mismatch (+6). "
                f"Got: '{desc}'"
            )
    else:
        feedback.append("C3: Phase 3 routine not found (+0)")

    # ---------------------------------------------------------------
    # C4-C9 (8 pts each): Each training day exists under the correct routine
    # ---------------------------------------------------------------
    criterion_labels = {
        ("phase1", "Upper Body Foundations"): "C4",
        ("phase1", "Lower Body Foundations"): "C5",
        ("phase2", "Heavy Upper"): "C6",
        ("phase2", "Heavy Lower"): "C7",
        ("phase3", "Explosive Upper"): "C8",
        ("phase3", "Explosive Lower"): "C9",
    }

    # Track which days have correct day-of-week for C10
    correct_dow_count = 0

    for phase_key, day_name, expected_dow in EXPECTED_DAYS:
        label = criterion_labels[(phase_key, day_name)]
        phase_data = phases[phase_key]
        days = phase_data.get("days", [])

        # Find the day by name (case-insensitive match)
        found_day = None
        for d in days:
            d_name = (d.get("name") or "").strip()
            if d_name.lower() == day_name.lower():
                found_day = d
                break

        if found_day is not None:
            score += 8
            feedback.append(
                f"{label}: '{day_name}' found in {EXPECTED_ROUTINE_NAMES[phase_key]} (+8)"
            )

            # Check day-of-week for C10
            dow_list = found_day.get("day_of_week", [])
            if isinstance(dow_list, list) and expected_dow in dow_list:
                correct_dow_count += 1
        else:
            feedback.append(
                f"{label}: '{day_name}' NOT found in {EXPECTED_ROUTINE_NAMES[phase_key]} (+0)"
            )

    # ---------------------------------------------------------------
    # C10 (16 pts): At least 4 of 6 days have correct day-of-week
    # ---------------------------------------------------------------
    if correct_dow_count >= 4:
        score += 16
        feedback.append(
            f"C10: {correct_dow_count}/6 days have correct day-of-week assignments (+16)"
        )
    elif correct_dow_count > 0:
        # Partial credit: 4 pts per correct assignment up to 12
        partial = min(correct_dow_count * 4, 12)
        score += partial
        feedback.append(
            f"C10: Only {correct_dow_count}/6 days have correct day-of-week "
            f"(need 4 for full credit) (+{partial})"
        )
    else:
        feedback.append("C10: No days have correct day-of-week assignments (+0)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback),
    }
