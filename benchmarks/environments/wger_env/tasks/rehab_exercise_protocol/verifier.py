#!/usr/bin/env python3
"""Verifier for rehab_exercise_protocol task.

Checks that the agent correctly:
1. Logged 6 historical body weight entries from Phase I hospitalization
2. Created 3 clinical measurement categories (6MWD, BP, RPE) with correct units
3. Logged 5 historical entries for each clinical measurement
4. Built a Phase II Cardiac Rehabilitation routine with 3 training days (correct DOW)
   and appropriate exercises
5. Created a heart-healthy nutrition plan with specified daily targets

Scoring (100 points total):
  C1  (12 pts): 6 weight entries on correct dates within ±0.3 kg (2 pts each)
  C2  ( 5 pts): "6-Minute Walk Distance" category with unit "m"
  C3  ( 5 pts): "Resting Systolic BP" category with unit "mmHg"
  C4  ( 5 pts): "Borg RPE Score" category with unit "RPE"
  C5  (10 pts): 5 correct 6MWD entries (within ±10 m)
  C6  (10 pts): 5 correct systolic BP entries (within ±2 mmHg)
  C7  (10 pts): 5 correct RPE entries (within ±1)
  C8  (10 pts): "Phase II Cardiac Rehabilitation Protocol" routine exists with correct description
  C9  ( 9 pts): All 3 named training days exist (3 pts each)
  C10 ( 6 pts): At least 2 days have correct day-of-week assignment (3 pts each)
  C11 ( 8 pts): At least 2 exercises assigned across training days
  C12 (10 pts): "Cardiac Heart-Healthy Eating Plan" nutrition plan exists
  C13 (10 pts): Energy goal 2100 kcal (±10) and macros: protein 95g, carbs 280g, fat 58g (any 2 of 3, ±5g)

Pass threshold: 58 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/rehab_protocol_result.json"

EXPECTED_WEIGHTS = {
    "2026-01-12": 88.5,
    "2026-01-19": 87.8,
    "2026-01-26": 87.2,
    "2026-02-02": 86.9,
    "2026-02-09": 86.4,
    "2026-02-16": 85.8,
}

EXPECTED_6MWD = {
    "2026-01-14": 310,
    "2026-01-28": 342,
    "2026-02-11": 378,
    "2026-02-25": 415,
    "2026-03-04": 448,
}

EXPECTED_BP = {
    "2026-01-14": 148,
    "2026-01-28": 143,
    "2026-02-11": 138,
    "2026-02-25": 134,
    "2026-03-04": 130,
}

EXPECTED_RPE = {
    "2026-01-14": 14,
    "2026-01-28": 13,
    "2026-02-11": 12,
    "2026-02-25": 12,
    "2026-03-04": 11,
}

EXPECTED_DAY_NAMES = {
    "Aerobic Warm-Up and Walking": 1,    # Monday
    "Low-Intensity Resistance Circuit": 3, # Wednesday
    "Active Recovery and Flexibility": 5,  # Friday
}


def verify_rehab_exercise_protocol(traj, env_info, task_info):
    """Verify the rehab exercise protocol task completion."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available in env_info",
        }

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result file {RESULT_PATH}: {e}",
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    weight_entries = result.get("weight_entries", {})
    measurement_data = result.get("measurement_data", {})
    routine_data = result.get("routine", {})
    plan_data = result.get("nutrition_plan", {})

    # Gate: do-nothing check
    any_weight = any(
        weight_entries.get(d, {}).get("exists", False) for d in EXPECTED_WEIGHTS
    )
    routine_found = routine_data.get("found", False)
    plan_found = plan_data.get("found", False)
    any_measure = any(
        measurement_data.get(c, {}).get("exists", False)
        for c in ["6-Minute Walk Distance", "Resting Systolic BP", "Borg RPE Score"]
    )

    if not any_weight and not routine_found and not plan_found and not any_measure:
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: No weight entries, routine, measurement categories, or nutrition plan found.",
        }

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # C1 (12 pts): 6 weight entries, 2 pts each within ±0.3 kg
    # ------------------------------------------------------------------
    weight_correct = 0
    for date_str, expected_kg in EXPECTED_WEIGHTS.items():
        entry = weight_entries.get(date_str, {})
        if entry.get("exists", False):
            actual_kg = float(entry.get("weight_kg") or 0)
            if abs(actual_kg - expected_kg) <= 0.3:
                weight_correct += 1

    c1_pts = weight_correct * 2
    score += c1_pts
    feedback_parts.append(f"C1({c1_pts}/12): {weight_correct}/6 weight entries correct")

    # ------------------------------------------------------------------
    # C2 (5 pts): 6-Minute Walk Distance with unit "m"
    # ------------------------------------------------------------------
    mwd_data = measurement_data.get("6-Minute Walk Distance", {})
    if mwd_data.get("exists", False):
        unit = str(mwd_data.get("unit", "")).strip().lower()
        if unit == "m":
            score += 5
            feedback_parts.append("C2(5/5): '6-Minute Walk Distance' category with unit 'm'")
        else:
            score += 2
            feedback_parts.append(f"C2(2/5): '6-Minute Walk Distance' exists but unit='{mwd_data.get('unit')}'")
    else:
        feedback_parts.append("C2(0/5): '6-Minute Walk Distance' NOT found")

    # ------------------------------------------------------------------
    # C3 (5 pts): Resting Systolic BP with unit "mmHg"
    # ------------------------------------------------------------------
    bp_data = measurement_data.get("Resting Systolic BP", {})
    if bp_data.get("exists", False):
        unit = str(bp_data.get("unit", "")).strip().lower()
        if unit == "mmhg":
            score += 5
            feedback_parts.append("C3(5/5): 'Resting Systolic BP' category with unit 'mmHg'")
        else:
            score += 2
            feedback_parts.append(f"C3(2/5): 'Resting Systolic BP' exists but unit='{bp_data.get('unit')}'")
    else:
        feedback_parts.append("C3(0/5): 'Resting Systolic BP' NOT found")

    # ------------------------------------------------------------------
    # C4 (5 pts): Borg RPE Score with unit "RPE"
    # ------------------------------------------------------------------
    rpe_data = measurement_data.get("Borg RPE Score", {})
    if rpe_data.get("exists", False):
        unit = str(rpe_data.get("unit", "")).strip().lower()
        if unit == "rpe":
            score += 5
            feedback_parts.append("C4(5/5): 'Borg RPE Score' category with unit 'RPE'")
        else:
            score += 2
            feedback_parts.append(f"C4(2/5): 'Borg RPE Score' exists but unit='{rpe_data.get('unit')}'")
    else:
        feedback_parts.append("C4(0/5): 'Borg RPE Score' NOT found")

    def count_entries_correct(data_dict, expected_dict, tolerance):
        correct = 0
        entries = data_dict.get("entries", {})
        for date_str, expected_val in expected_dict.items():
            actual = entries.get(date_str)
            if actual is not None and abs(float(actual) - expected_val) <= tolerance:
                correct += 1
        return correct

    # ------------------------------------------------------------------
    # C5 (10 pts): 5 correct 6MWD entries (±10 m)
    # ------------------------------------------------------------------
    mwd_correct = count_entries_correct(mwd_data, EXPECTED_6MWD, 10) if mwd_data.get("exists") else 0
    c5_pts = 10 if mwd_correct == 5 else (6 if mwd_correct >= 3 else (3 if mwd_correct >= 1 else 0))
    score += c5_pts
    feedback_parts.append(f"C5({c5_pts}/10): {mwd_correct}/5 6MWD entries correct")

    # ------------------------------------------------------------------
    # C6 (10 pts): 5 correct BP entries (±2 mmHg)
    # ------------------------------------------------------------------
    bp_correct = count_entries_correct(bp_data, EXPECTED_BP, 2) if bp_data.get("exists") else 0
    c6_pts = 10 if bp_correct == 5 else (6 if bp_correct >= 3 else (3 if bp_correct >= 1 else 0))
    score += c6_pts
    feedback_parts.append(f"C6({c6_pts}/10): {bp_correct}/5 BP entries correct")

    # ------------------------------------------------------------------
    # C7 (10 pts): 5 correct RPE entries (±1)
    # ------------------------------------------------------------------
    rpe_correct = count_entries_correct(rpe_data, EXPECTED_RPE, 1) if rpe_data.get("exists") else 0
    c7_pts = 10 if rpe_correct == 5 else (6 if rpe_correct >= 3 else (3 if rpe_correct >= 1 else 0))
    score += c7_pts
    feedback_parts.append(f"C7({c7_pts}/10): {rpe_correct}/5 RPE entries correct")

    # ------------------------------------------------------------------
    # C8 (10 pts): Routine exists with correct description
    # ------------------------------------------------------------------
    if routine_found:
        desc = (routine_data.get("description") or "").strip()
        expected_desc = "Supervised outpatient cardiac rehab: 12-week progressive aerobic and resistance program"
        if expected_desc.lower() in desc.lower() or desc.lower() in expected_desc.lower():
            score += 10
            feedback_parts.append("C8(10/10): Routine exists with correct description")
        else:
            score += 4
            feedback_parts.append(f"C8(4/10): Routine exists but description mismatch: '{desc[:80]}'")
    else:
        feedback_parts.append("C8(0/10): 'Phase II Cardiac Rehabilitation Protocol' routine NOT found")

    # ------------------------------------------------------------------
    # C9 (9 pts): All 3 named training days exist (3 pts each)
    # ------------------------------------------------------------------
    days = routine_data.get("days", [])
    day_names_found = {d.get("name", "").strip(): d for d in days}

    correct_dow_count = 0
    days_found_count = 0
    for day_name, expected_dow in EXPECTED_DAY_NAMES.items():
        if day_name in day_names_found:
            days_found_count += 1
            dow_list = day_names_found[day_name].get("day_of_week", [])
            if expected_dow in dow_list:
                correct_dow_count += 1

    c9_pts = days_found_count * 3
    score += c9_pts
    feedback_parts.append(f"C9({c9_pts}/9): {days_found_count}/3 training days found")

    # ------------------------------------------------------------------
    # C10 (6 pts): At least 2 days have correct DOW (3 pts each)
    # ------------------------------------------------------------------
    c10_pts = min(correct_dow_count * 3, 6)
    score += c10_pts
    feedback_parts.append(f"C10({c10_pts}/6): {correct_dow_count}/3 days have correct day-of-week")

    # ------------------------------------------------------------------
    # C11 (8 pts): At least 2 exercises assigned
    # ------------------------------------------------------------------
    total_exercises = sum(len(d.get("exercises", [])) for d in days)
    if total_exercises >= 3:
        score += 8
        feedback_parts.append(f"C11(8/8): {total_exercises} exercises assigned")
    elif total_exercises >= 2:
        score += 5
        feedback_parts.append(f"C11(5/8): {total_exercises} exercises assigned")
    elif total_exercises >= 1:
        score += 2
        feedback_parts.append(f"C11(2/8): {total_exercises} exercises assigned")
    else:
        feedback_parts.append("C11(0/8): No exercises assigned")

    # ------------------------------------------------------------------
    # C12 (10 pts): Nutrition plan exists
    # ------------------------------------------------------------------
    if plan_found:
        score += 10
        feedback_parts.append("C12(10/10): 'Cardiac Heart-Healthy Eating Plan' plan exists")
    else:
        feedback_parts.append("C12(0/10): Nutrition plan NOT found")

    # ------------------------------------------------------------------
    # C13 (10 pts): Energy goal 2100 kcal (±10) + macros (any 2 of 3, ±5g)
    # ------------------------------------------------------------------
    if plan_found:
        goal_energy = float(plan_data.get("goal_energy") or 0)
        energy_ok = abs(goal_energy - 2100) <= 10

        macros_correct = 0
        for field, expected in [
            ("goal_protein", 95),
            ("goal_carbohydrates", 280),
            ("goal_fat", 58),
        ]:
            actual = float(plan_data.get(field) or 0)
            if abs(actual - expected) <= 5:
                macros_correct += 1

        if energy_ok and macros_correct >= 2:
            score += 10
            feedback_parts.append(f"C13(10/10): Energy {goal_energy}kcal OK, {macros_correct}/3 macros correct")
        elif energy_ok or macros_correct >= 2:
            score += 5
            feedback_parts.append(f"C13(5/10): Energy={goal_energy}kcal, {macros_correct}/3 macros correct")
        elif macros_correct == 1 or goal_energy > 0:
            score += 2
            feedback_parts.append(f"C13(2/10): Energy={goal_energy}kcal, {macros_correct}/3 macros correct")
        else:
            feedback_parts.append("C13(0/10): No energy or macro goals set")
    else:
        feedback_parts.append("C13(0/10): No plan to check energy/macros")

    passed = score >= 58
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": (
            f"Total: {score}/100 (pass threshold: 58) | "
            + " | ".join(feedback_parts)
        ),
    }
