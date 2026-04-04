#!/usr/bin/env python3
"""Verifier for endurance_athlete_periodization task.

Checks that the agent correctly:
1. Logged 8 historical body weight entries on specific dates
2. Created 2 physiological measurement categories with correct units
3. Logged 4 historical entries for each measurement category
4. Built a 16-week periodized training routine with 6 named days and correct DOW assignments
5. Assigned exercises across the training days
6. Created a competition nutrition plan with correct macro targets

Scoring (100 points total):
  C1  (16 pts): 8 weight entries logged on correct dates (2 pts each, within ±0.3 kg)
  C2  ( 5 pts): "Cooper Test Distance" category exists with unit "m"
  C3  ( 5 pts): "Resting Heart Rate" category exists with unit "bpm"
  C4  (10 pts): 4 Cooper Test Distance entries correct (within ±20 m)
  C5  (10 pts): 4 Resting HR entries correct (within ±1 bpm)
  C6  (10 pts): Routine "16-Week Marathon Spring Periodization" exists with correct description
  C7  (12 pts): At least 5 of 6 named training days exist
  C8  ( 8 pts): At least 4 days have correct day-of-week assignment
  C9  ( 4 pts): At least 4 exercises assigned across all days
  C10 (10 pts): "Marathon Competition Phase - Race Week" nutrition plan exists
  C11 (10 pts): Energy goal 3200 kcal (±10)
  C12 (10 pts): Macros correct: protein 145g, carbs 480g, fat 75g (any 2 of 3, ±5g)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/endurance_periodization_result.json"

EXPECTED_WEIGHTS = {
    "2026-01-06": 68.2,
    "2026-01-13": 67.9,
    "2026-01-20": 67.5,
    "2026-01-27": 67.8,
    "2026-02-03": 67.4,
    "2026-02-10": 67.1,
    "2026-02-17": 66.8,
    "2026-02-24": 66.5,
}

EXPECTED_COOPER = {
    "2026-01-10": 3420,
    "2026-01-24": 3465,
    "2026-02-07": 3510,
    "2026-02-21": 3555,
}

EXPECTED_RHR = {
    "2026-01-10": 52,
    "2026-01-24": 51,
    "2026-02-07": 50,
    "2026-02-21": 49,
}

EXPECTED_DAY_NAMES = {
    "Base Phase - Long Run": 7,      # Sunday
    "Base Phase - Easy Recovery": 3,  # Wednesday
    "Build Phase - Tempo Work": 2,    # Tuesday
    "Build Phase - Long Intervals": 5, # Friday
    "Peak Phase - Race Pace": 2,      # Tuesday
    "Taper Phase - Shakeout": 5,      # Friday
}


def verify_endurance_athlete_periodization(traj, env_info, task_info):
    """Verify the endurance athlete periodization task completion."""

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
        for c in ["Cooper Test Distance", "Resting Heart Rate"]
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
    # C1 (16 pts): 8 weight entries, 2 pts each within ±0.3 kg
    # ------------------------------------------------------------------
    weight_correct = 0
    weight_details = []
    for date_str, expected_kg in EXPECTED_WEIGHTS.items():
        entry = weight_entries.get(date_str, {})
        if entry.get("exists", False):
            actual_kg = float(entry.get("weight_kg") or 0)
            if abs(actual_kg - expected_kg) <= 0.3:
                weight_correct += 1
                weight_details.append(f"{date_str}: {actual_kg}kg OK")
            else:
                weight_details.append(
                    f"{date_str}: {actual_kg}kg (expected {expected_kg})"
                )
        else:
            weight_details.append(f"{date_str}: MISSING")

    c1_pts = weight_correct * 2
    score += c1_pts
    feedback_parts.append(
        f"C1({c1_pts}/16): {weight_correct}/8 weight entries correct"
    )

    # ------------------------------------------------------------------
    # C2 (5 pts): Cooper Test Distance category with unit "m"
    # ------------------------------------------------------------------
    cd_data = measurement_data.get("Cooper Test Distance", {})
    if cd_data.get("exists", False):
        unit = str(cd_data.get("unit", "")).strip().lower()
        if unit == "m":
            score += 5
            feedback_parts.append("C2(5/5): 'Cooper Test Distance' category exists with unit 'm'")
        else:
            score += 2
            feedback_parts.append(f"C2(2/5): 'Cooper Test Distance' exists but unit='{cd_data.get('unit')}'")
    else:
        feedback_parts.append("C2(0/5): 'Cooper Test Distance' NOT found")

    # ------------------------------------------------------------------
    # C3 (5 pts): Resting Heart Rate category with unit "bpm"
    # ------------------------------------------------------------------
    rhr_data = measurement_data.get("Resting Heart Rate", {})
    if rhr_data.get("exists", False):
        unit = str(rhr_data.get("unit", "")).strip().lower()
        if unit == "bpm":
            score += 5
            feedback_parts.append("C3(5/5): 'Resting Heart Rate' category exists with unit 'bpm'")
        else:
            score += 2
            feedback_parts.append(f"C3(2/5): 'Resting Heart Rate' exists but unit='{rhr_data.get('unit')}'")
    else:
        feedback_parts.append("C3(0/5): 'Resting Heart Rate' NOT found")

    # ------------------------------------------------------------------
    # C4 (10 pts): 4 Cooper Test entries within ±20 m
    # ------------------------------------------------------------------
    cooper_correct = 0
    cooper_details = []
    if cd_data.get("exists", False):
        entries = cd_data.get("entries", {})
        for date_str, expected_val in EXPECTED_COOPER.items():
            actual = entries.get(date_str)
            if actual is not None and abs(float(actual) - expected_val) <= 20:
                cooper_correct += 1
                cooper_details.append(f"{date_str}:{actual}m OK")
            else:
                cooper_details.append(f"{date_str}:{actual} (exp {expected_val})")

    c4_pts = 0
    if cooper_correct == 4:
        c4_pts = 10
    elif cooper_correct >= 2:
        c4_pts = 5
    elif cooper_correct == 1:
        c4_pts = 2
    score += c4_pts
    feedback_parts.append(f"C4({c4_pts}/10): {cooper_correct}/4 Cooper entries correct [{'; '.join(cooper_details)}]")

    # ------------------------------------------------------------------
    # C5 (10 pts): 4 Resting HR entries within ±1 bpm
    # ------------------------------------------------------------------
    rhr_correct = 0
    rhr_details = []
    if rhr_data.get("exists", False):
        entries = rhr_data.get("entries", {})
        for date_str, expected_val in EXPECTED_RHR.items():
            actual = entries.get(date_str)
            if actual is not None and abs(float(actual) - expected_val) <= 1:
                rhr_correct += 1
                rhr_details.append(f"{date_str}:{actual}bpm OK")
            else:
                rhr_details.append(f"{date_str}:{actual} (exp {expected_val})")

    c5_pts = 0
    if rhr_correct == 4:
        c5_pts = 10
    elif rhr_correct >= 2:
        c5_pts = 5
    elif rhr_correct == 1:
        c5_pts = 2
    score += c5_pts
    feedback_parts.append(f"C5({c5_pts}/10): {rhr_correct}/4 Resting HR entries correct [{'; '.join(rhr_details)}]")

    # ------------------------------------------------------------------
    # C6 (10 pts): Routine exists with correct description
    # ------------------------------------------------------------------
    if routine_found:
        desc = (routine_data.get("description") or "").strip()
        expected_desc = "Elite marathon runner spring race preparation: Base, Build, Peak, Taper phases"
        if expected_desc.lower() in desc.lower() or desc.lower() in expected_desc.lower():
            score += 10
            feedback_parts.append("C6(10/10): Routine exists with correct description")
        else:
            score += 4
            feedback_parts.append(f"C6(4/10): Routine exists but description mismatch: '{desc[:80]}'")
    else:
        feedback_parts.append("C6(0/10): '16-Week Marathon Spring Periodization' routine NOT found")

    # ------------------------------------------------------------------
    # C7 (12 pts): At least 5 of 6 named training days exist (2 pts each)
    # ------------------------------------------------------------------
    days = routine_data.get("days", [])
    day_names_found = {d.get("name", "").strip(): d for d in days}

    days_found_count = 0
    correct_dow_count = 0
    for day_name, expected_dow in EXPECTED_DAY_NAMES.items():
        if day_name in day_names_found:
            days_found_count += 1
            dow_list = day_names_found[day_name].get("day_of_week", [])
            if expected_dow in dow_list:
                correct_dow_count += 1

    c7_pts = min(days_found_count * 2, 12)
    score += c7_pts
    feedback_parts.append(f"C7({c7_pts}/12): {days_found_count}/6 training days found")

    # ------------------------------------------------------------------
    # C8 (8 pts): At least 4 days have correct day-of-week
    # ------------------------------------------------------------------
    if correct_dow_count >= 5:
        score += 8
        feedback_parts.append(f"C8(8/8): {correct_dow_count}/6 days have correct day-of-week")
    elif correct_dow_count >= 4:
        score += 6
        feedback_parts.append(f"C8(6/8): {correct_dow_count}/6 days have correct day-of-week")
    elif correct_dow_count >= 2:
        score += 3
        feedback_parts.append(f"C8(3/8): {correct_dow_count}/6 days have correct day-of-week")
    else:
        feedback_parts.append(f"C8(0/8): {correct_dow_count}/6 days have correct day-of-week")

    # ------------------------------------------------------------------
    # C9 (4 pts): At least 4 exercises assigned across all days
    # ------------------------------------------------------------------
    total_exercises = sum(len(d.get("exercises", [])) for d in days)
    if total_exercises >= 6:
        score += 4
        feedback_parts.append(f"C9(4/4): {total_exercises} exercises assigned")
    elif total_exercises >= 4:
        score += 3
        feedback_parts.append(f"C9(3/4): {total_exercises} exercises assigned")
    elif total_exercises >= 2:
        score += 1
        feedback_parts.append(f"C9(1/4): {total_exercises} exercises assigned")
    else:
        feedback_parts.append(f"C9(0/4): {total_exercises} exercises assigned")

    # ------------------------------------------------------------------
    # C10 (10 pts): Nutrition plan exists
    # ------------------------------------------------------------------
    if plan_found:
        score += 10
        feedback_parts.append("C10(10/10): 'Marathon Competition Phase - Race Week' plan exists")
    else:
        feedback_parts.append("C10(0/10): Nutrition plan NOT found")

    # ------------------------------------------------------------------
    # C11 (10 pts): Energy goal 3200 kcal (±10)
    # ------------------------------------------------------------------
    if plan_found:
        goal_energy = float(plan_data.get("goal_energy") or 0)
        if abs(goal_energy - 3200) <= 10:
            score += 10
            feedback_parts.append(f"C11(10/10): Energy goal = {goal_energy} kcal")
        elif goal_energy > 0:
            score += 3
            feedback_parts.append(f"C11(3/10): Energy goal = {goal_energy} (expected 3200)")
        else:
            feedback_parts.append("C11(0/10): Energy goal not set")
    else:
        feedback_parts.append("C11(0/10): No plan to check energy goal")

    # ------------------------------------------------------------------
    # C12 (10 pts): Macros correct (any 2 of 3, within ±5g)
    # ------------------------------------------------------------------
    if plan_found:
        macros_correct = 0
        macro_details = []
        for field, expected, label in [
            ("goal_protein", 145, "Protein"),
            ("goal_carbohydrates", 480, "Carbs"),
            ("goal_fat", 75, "Fat"),
        ]:
            actual = float(plan_data.get(field) or 0)
            if abs(actual - expected) <= 5:
                macros_correct += 1
                macro_details.append(f"{label}={actual}g OK")
            else:
                macro_details.append(f"{label}={actual}g (exp {expected}g)")

        if macros_correct >= 2:
            score += 10
            feedback_parts.append(f"C12(10/10): {macros_correct}/3 macros correct [{'; '.join(macro_details)}]")
        elif macros_correct == 1:
            score += 4
            feedback_parts.append(f"C12(4/10): {macros_correct}/3 macros correct [{'; '.join(macro_details)}]")
        else:
            feedback_parts.append(f"C12(0/10): {macros_correct}/3 macros correct [{'; '.join(macro_details)}]")
    else:
        feedback_parts.append("C12(0/10): No plan to check macros")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": (
            f"Total: {score}/100 (pass threshold: 60) | "
            + " | ".join(feedback_parts)
        ),
    }
