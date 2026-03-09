#!/usr/bin/env python3
"""Verifier for athlete_body_composition_program task.

Checks that the agent correctly:
1. Logged 5 historical body weight entries on specific dates
2. Created 2 measurement tracking categories with correct units
3. Created a workout routine with 3 training days and exercise assignments
4. Created a nutrition plan with specific macronutrient goals

Scoring (100 points total):
  C1  (15 pts): 5 weight entries logged on correct dates with correct values
  C2  ( 5 pts): "Skinfold Sum" measurement category exists with unit "mm"
  C3  ( 5 pts): "Grip Strength" measurement category exists with unit "kg"
  C4  (10 pts): "Off-Season Wrestling Strength" routine exists with correct description
  C5  ( 5 pts): "Upper Push/Pull" training day exists (Tuesday)
  C6  ( 5 pts): "Lower Compound" training day exists (Thursday)
  C7  ( 5 pts): "Full Body Power" training day exists (Saturday)
  C8  (10 pts): At least 3 exercises correctly assigned across the training days
  C9  (10 pts): Nutrition plan exists with description "Wrestling Weight Management - Off-Season"
  C10 (10 pts): Energy goal = 2600 kcal
  C11 (10 pts): Protein = 160g, Carbs = 300g, Fat = 80g (any 2 of 3 correct)
  C12 (10 pts): At least 2 training days have correct day-of-week assignments

Pass threshold: 65 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/athlete_body_comp_result.json"

# Expected weight entries
EXPECTED_WEIGHTS = {
    "2026-02-03": 79.4,
    "2026-02-10": 78.9,
    "2026-02-17": 78.2,
    "2026-02-24": 77.8,
    "2026-03-03": 77.1,
}

# Day-of-week mapping: wger uses 1=Monday ... 7=Sunday
EXPECTED_DAY_DOW = {
    "Upper Push/Pull": 2,    # Tuesday
    "Lower Compound": 4,     # Thursday
    "Full Body Power": 6,    # Saturday
}


def verify_athlete_body_composition_program(traj, env_info, task_info):
    """Verify the athlete body composition program task completion."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available in env_info",
        }

    # Copy result JSON from the environment
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
    categories = result.get("measurement_categories", {})
    routine_data = result.get("routine", {})
    plan_data = result.get("nutrition_plan", {})

    # -------------------------------------------------------------------
    # Gate: If no weight entries, no routine, no plan -> do-nothing
    # -------------------------------------------------------------------
    any_weight = any(
        weight_entries.get(d, {}).get("exists", False)
        for d in EXPECTED_WEIGHTS
    )
    routine_found = routine_data.get("found", False)
    plan_found = plan_data.get("found", False)

    if not any_weight and not routine_found and not plan_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: No weight entries, routine, or nutrition plan created.",
        }

    score = 0
    feedback_parts = []

    # -------------------------------------------------------------------
    # C1 (15 pts): Weight entries on correct dates with correct values
    # 3 pts per correct entry (date exists + weight within 0.5 kg)
    # -------------------------------------------------------------------
    weight_correct = 0
    weight_details = []
    for date_str, expected_kg in EXPECTED_WEIGHTS.items():
        entry = weight_entries.get(date_str, {})
        if entry.get("exists", False):
            actual_kg = entry.get("weight_kg", 0)
            if abs(actual_kg - expected_kg) <= 0.5:
                weight_correct += 1
                weight_details.append(f"{date_str}: {actual_kg}kg OK")
            else:
                weight_details.append(
                    f"{date_str}: {actual_kg}kg (expected {expected_kg})"
                )
        else:
            weight_details.append(f"{date_str}: NOT FOUND")

    c1_pts = weight_correct * 3
    score += c1_pts
    feedback_parts.append(
        f"C1({c1_pts}/15): {weight_correct}/5 weight entries correct "
        f"[{'; '.join(weight_details)}]"
    )

    # -------------------------------------------------------------------
    # C2 (5 pts): "Skinfold Sum" with unit "mm"
    # -------------------------------------------------------------------
    sf_data = categories.get("Skinfold Sum", {})
    if sf_data.get("exists", False):
        sf_unit = str(sf_data.get("unit", "")).strip().lower()
        if sf_unit == "mm":
            score += 5
            feedback_parts.append("C2(5/5): 'Skinfold Sum' exists with unit 'mm'")
        else:
            score += 2
            feedback_parts.append(
                f"C2(2/5): 'Skinfold Sum' exists but unit is '{sf_data.get('unit', '')}'"
            )
    else:
        feedback_parts.append("C2(0/5): 'Skinfold Sum' NOT found")

    # -------------------------------------------------------------------
    # C3 (5 pts): "Grip Strength" with unit "kg"
    # -------------------------------------------------------------------
    gs_data = categories.get("Grip Strength", {})
    if gs_data.get("exists", False):
        gs_unit = str(gs_data.get("unit", "")).strip().lower()
        if gs_unit == "kg":
            score += 5
            feedback_parts.append("C3(5/5): 'Grip Strength' exists with unit 'kg'")
        else:
            score += 2
            feedback_parts.append(
                f"C3(2/5): 'Grip Strength' exists but unit is '{gs_data.get('unit', '')}'"
            )
    else:
        feedback_parts.append("C3(0/5): 'Grip Strength' NOT found")

    # -------------------------------------------------------------------
    # C4 (10 pts): Routine exists with correct description
    # -------------------------------------------------------------------
    if routine_found:
        desc = (routine_data.get("description") or "").strip()
        expected_desc = "8-week hypertrophy and strength block for 74kg wrestler"
        if expected_desc.lower() in desc.lower() or desc.lower() in expected_desc.lower():
            score += 10
            feedback_parts.append("C4(10/10): Routine exists with correct description")
        else:
            score += 5
            feedback_parts.append(
                f"C4(5/10): Routine exists but description mismatch: '{desc[:60]}'"
            )
    else:
        feedback_parts.append("C4(0/10): 'Off-Season Wrestling Strength' routine NOT found")

    # -------------------------------------------------------------------
    # C5-C7 (5 pts each): Training days exist
    # -------------------------------------------------------------------
    days = routine_data.get("days", [])
    day_names_found = {d.get("name", "").strip(): d for d in days}

    correct_dow_count = 0
    for day_name, expected_dow, label in [
        ("Upper Push/Pull", 2, "C5"),
        ("Lower Compound", 4, "C6"),
        ("Full Body Power", 6, "C7"),
    ]:
        if day_name in day_names_found:
            score += 5
            feedback_parts.append(f"{label}(5/5): '{day_name}' day exists")
            dow_list = day_names_found[day_name].get("day_of_week", [])
            if expected_dow in dow_list:
                correct_dow_count += 1
        else:
            feedback_parts.append(f"{label}(0/5): '{day_name}' day NOT found")

    # -------------------------------------------------------------------
    # C8 (10 pts): At least 3 exercises correctly assigned
    # -------------------------------------------------------------------
    total_exercises = 0
    for d in days:
        exercises = d.get("exercises", [])
        total_exercises += len(exercises)

    if total_exercises >= 5:
        score += 10
        feedback_parts.append(
            f"C8(10/10): {total_exercises} exercises assigned (need >= 5)"
        )
    elif total_exercises >= 3:
        score += 5
        feedback_parts.append(
            f"C8(5/10): {total_exercises} exercises assigned (partial, need >= 5)"
        )
    else:
        feedback_parts.append(
            f"C8(0/10): Only {total_exercises} exercises assigned (need >= 3)"
        )

    # -------------------------------------------------------------------
    # C9 (10 pts): Nutrition plan exists
    # -------------------------------------------------------------------
    if plan_found:
        score += 10
        feedback_parts.append(
            "C9(10/10): 'Wrestling Weight Management - Off-Season' plan exists"
        )
    else:
        feedback_parts.append(
            "C9(0/10): 'Wrestling Weight Management - Off-Season' plan NOT found"
        )

    # -------------------------------------------------------------------
    # C10 (10 pts): Energy goal = 2600 kcal
    # -------------------------------------------------------------------
    if plan_found:
        goal_energy = plan_data.get("goal_energy", 0)
        try:
            goal_energy = float(goal_energy)
        except (ValueError, TypeError):
            goal_energy = 0
        if abs(goal_energy - 2600) < 10:
            score += 10
            feedback_parts.append(f"C10(10/10): Energy goal = {goal_energy}")
        elif goal_energy > 0:
            score += 3
            feedback_parts.append(
                f"C10(3/10): Energy goal = {goal_energy} (expected 2600)"
            )
        else:
            feedback_parts.append("C10(0/10): Energy goal not set")
    else:
        feedback_parts.append("C10(0/10): No plan to check energy goal")

    # -------------------------------------------------------------------
    # C11 (10 pts): Macros correct (any 2 of 3)
    # -------------------------------------------------------------------
    if plan_found:
        macros_correct = 0
        macro_details = []
        for field, expected, label in [
            ("goal_protein", 160, "Protein"),
            ("goal_carbohydrates", 300, "Carbs"),
            ("goal_fat", 80, "Fat"),
        ]:
            actual = plan_data.get(field, 0)
            try:
                actual = float(actual)
            except (ValueError, TypeError):
                actual = 0
            if abs(actual - expected) < 5:
                macros_correct += 1
                macro_details.append(f"{label}={actual}g OK")
            else:
                macro_details.append(f"{label}={actual}g (expected {expected}g)")

        if macros_correct >= 2:
            score += 10
            feedback_parts.append(
                f"C11(10/10): {macros_correct}/3 macros correct [{'; '.join(macro_details)}]"
            )
        elif macros_correct == 1:
            score += 4
            feedback_parts.append(
                f"C11(4/10): {macros_correct}/3 macros correct [{'; '.join(macro_details)}]"
            )
        else:
            feedback_parts.append(
                f"C11(0/10): {macros_correct}/3 macros correct [{'; '.join(macro_details)}]"
            )
    else:
        feedback_parts.append("C11(0/10): No plan to check macros")

    # -------------------------------------------------------------------
    # C12 (10 pts): At least 2 training days have correct day-of-week
    # -------------------------------------------------------------------
    if correct_dow_count >= 2:
        score += 10
        feedback_parts.append(
            f"C12(10/10): {correct_dow_count}/3 days have correct day-of-week"
        )
    elif correct_dow_count == 1:
        score += 4
        feedback_parts.append(
            f"C12(4/10): {correct_dow_count}/3 days have correct day-of-week"
        )
    else:
        feedback_parts.append("C12(0/10): No days have correct day-of-week")

    # -------------------------------------------------------------------
    # Final result
    # -------------------------------------------------------------------
    passed = score >= 65

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": (
            f"Total: {score}/100 (pass threshold: 65) | "
            + " | ".join(feedback_parts)
        ),
    }
