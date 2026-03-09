#!/usr/bin/env python3
"""Verifier for corporate_health_screening_program task.

Checks that the agent correctly:
1. Registered 3 employees as wger users with correct usernames and emails
2. Created a group ergonomic wellness routine with 3 training days, correct DOW, and exercises
3. Created a nutrition plan with correct macro targets and 5 named meals
4. Created 2 body composition measurement categories with correct units

Scoring (100 points total):
  C1  (18 pts): 3 employees registered with correct usernames (6 pts each)
  C2  ( 9 pts): 3 employees have correct email addresses (3 pts each)
  C3  (10 pts): "Meridian Ergonomic Wellness Circuit" routine exists with correct description
  C4  ( 9 pts): All 3 named training days exist (3 pts each)
  C5  ( 6 pts): At least 2 days have correct day-of-week assignment (3 pts each)
  C6  ( 4 pts): At least 3 exercises assigned across training days
  C7  (10 pts): "Meridian Metabolic Risk Reduction Plan" nutrition plan exists
  C8  (10 pts): Nutrition plan macros: energy 2200 kcal, protein 110g, carbs 270g, fat 62g (any 3 of 4)
  C9  (10 pts): At least 4 of 5 correct meals in nutrition plan
  C10 ( 7 pts): "Waist Circumference" measurement category with unit "cm"
  C11 ( 7 pts): "Resting Heart Rate" measurement category with unit "bpm"

Pass threshold: 70 points

Anti-pattern 4 check:
  Max score WITHOUT macros (C8=0), meals (C9=0), categories (C10=0, C11=0):
    C1(18)+C2(9)+C3(10)+C4(9)+C5(6)+C6(4)+C7(10) = 66 < 70 ✓
  Agent must complete at least one of: macros, meals, or measurement categories
  to reach 70, which ensures substantive task completion.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/corp_health_result.json"

EXPECTED_USERS = [
    {"username": "dwilliams_meridian", "email": "d.williams@meridian-ind.com"},
    {"username": "rparker_meridian", "email": "r.parker@meridian-ind.com"},
    {"username": "lchavez_meridian", "email": "l.chavez@meridian-ind.com"},
]

EXPECTED_DAY_NAMES = {
    "Cardio and Core Activation": 1,      # Monday
    "Upper Body Resistance": 3,            # Wednesday
    "Lower Body Mobility and Strength": 5, # Friday
}

EXPECTED_MEALS = [
    "Whole-Grain Breakfast",
    "Mid-Morning Snack",
    "Balanced Lunch",
    "Pre-Workout Snack",
    "Heart-Healthy Dinner",
]


def count_matching_meals(actual_names, expected_names):
    actual_lower = {n.strip().lower() for n in actual_names if n}
    return sum(1 for m in expected_names if m.strip().lower() in actual_lower)


def verify_corporate_health_screening_program(traj, env_info, task_info):
    """Verify the corporate health screening program task completion."""

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

    users_data = {u["username"]: u for u in result.get("users", [])}
    routine_data = result.get("routine", {})
    plan_data = result.get("nutrition_plan", {})
    measurement_data = result.get("measurement_categories", {})

    # Gate: do-nothing check
    any_user = any(users_data.get(u["username"], {}).get("exists", False) for u in EXPECTED_USERS)
    routine_found = routine_data.get("found", False)
    plan_found = plan_data.get("found", False)
    any_measure = any(
        measurement_data.get(c, {}).get("exists", False)
        for c in ["Waist Circumference", "Resting Heart Rate"]
    )

    if not any_user and not routine_found and not plan_found and not any_measure:
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: No users registered, routine, nutrition plan, or measurement categories found.",
        }

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # C1 (18 pts): 3 employees registered with correct usernames (6 pts each)
    # ------------------------------------------------------------------
    users_registered = 0
    for eu in EXPECTED_USERS:
        udata = users_data.get(eu["username"], {})
        if udata.get("exists", False):
            users_registered += 1

    c1_pts = users_registered * 6
    score += c1_pts
    feedback_parts.append(f"C1({c1_pts}/18): {users_registered}/3 employees registered")

    # ------------------------------------------------------------------
    # C2 (9 pts): Correct email addresses (3 pts each)
    # ------------------------------------------------------------------
    emails_correct = 0
    for eu in EXPECTED_USERS:
        udata = users_data.get(eu["username"], {})
        if udata.get("exists", False) and udata.get("email_correct", False):
            emails_correct += 1

    c2_pts = emails_correct * 3
    score += c2_pts
    feedback_parts.append(f"C2({c2_pts}/9): {emails_correct}/3 employees have correct email")

    # ------------------------------------------------------------------
    # C3 (10 pts): Routine exists with correct description
    # ------------------------------------------------------------------
    if routine_found:
        desc = (routine_data.get("description") or "").strip()
        expected_desc = "12-week cardiovascular risk reduction program for sedentary manufacturing workers"
        if expected_desc.lower() in desc.lower() or desc.lower() in expected_desc.lower():
            score += 10
            feedback_parts.append("C3(10/10): Routine exists with correct description")
        else:
            score += 4
            feedback_parts.append(f"C3(4/10): Routine exists but description mismatch: '{desc[:80]}'")
    else:
        feedback_parts.append("C3(0/10): 'Meridian Ergonomic Wellness Circuit' routine NOT found")

    # ------------------------------------------------------------------
    # C4 (9 pts): All 3 named training days exist (3 pts each)
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

    c4_pts = days_found_count * 3
    score += c4_pts
    feedback_parts.append(f"C4({c4_pts}/9): {days_found_count}/3 training days found")

    # ------------------------------------------------------------------
    # C5 (6 pts): At least 2 days have correct DOW (3 pts each)
    # ------------------------------------------------------------------
    c5_pts = min(correct_dow_count * 3, 6)
    score += c5_pts
    feedback_parts.append(f"C5({c5_pts}/6): {correct_dow_count}/3 days have correct day-of-week")

    # ------------------------------------------------------------------
    # C6 (4 pts): At least 3 exercises assigned
    # ------------------------------------------------------------------
    total_exercises = sum(len(d.get("exercises", [])) for d in days)
    if total_exercises >= 4:
        score += 4
        feedback_parts.append(f"C6(4/4): {total_exercises} exercises assigned")
    elif total_exercises >= 3:
        score += 3
        feedback_parts.append(f"C6(3/4): {total_exercises} exercises assigned")
    elif total_exercises >= 1:
        score += 1
        feedback_parts.append(f"C6(1/4): {total_exercises} exercises assigned")
    else:
        feedback_parts.append("C6(0/4): No exercises assigned")

    # ------------------------------------------------------------------
    # C7 (10 pts): Nutrition plan exists
    # ------------------------------------------------------------------
    if plan_found:
        score += 10
        feedback_parts.append("C7(10/10): 'Meridian Metabolic Risk Reduction Plan' exists")
    else:
        feedback_parts.append("C7(0/10): Nutrition plan NOT found")

    # ------------------------------------------------------------------
    # C8 (10 pts): Nutrition plan macros (any 3 of 4)
    # ------------------------------------------------------------------
    if plan_found:
        macro_ok = 0
        macro_details = []
        for field, expected, label, tol in [
            ("goal_energy", 2200, "Energy", 15),
            ("goal_protein", 110, "Protein", 5),
            ("goal_carbohydrates", 270, "Carbs", 5),
            ("goal_fat", 62, "Fat", 5),
        ]:
            actual = float(plan_data.get(field) or 0)
            if abs(actual - expected) <= tol:
                macro_ok += 1
                macro_details.append(f"{label}={actual} OK")
            else:
                macro_details.append(f"{label}={actual}(exp {expected})")

        c8_pts = 10 if macro_ok >= 3 else (6 if macro_ok == 2 else (3 if macro_ok == 1 else 0))
        score += c8_pts
        feedback_parts.append(f"C8({c8_pts}/10): {macro_ok}/4 macros correct [{'; '.join(macro_details)}]")
    else:
        feedback_parts.append("C8(0/10): No plan to check macros")

    # ------------------------------------------------------------------
    # C9 (10 pts): At least 4 of 5 correct meals
    # ------------------------------------------------------------------
    if plan_found:
        actual_meal_names = plan_data.get("meal_names", [])
        meals_found = count_matching_meals(actual_meal_names, EXPECTED_MEALS)
        c9_pts = 10 if meals_found >= 4 else (7 if meals_found == 3 else (4 if meals_found == 2 else (2 if meals_found >= 1 else 0)))
        score += c9_pts
        feedback_parts.append(f"C9({c9_pts}/10): {meals_found}/5 meals correct [found: {actual_meal_names}]")
    else:
        feedback_parts.append("C9(0/10): No plan to check meals")

    # ------------------------------------------------------------------
    # C10 (7 pts): Waist Circumference with unit "cm"
    # ------------------------------------------------------------------
    wc_data = measurement_data.get("Waist Circumference", {})
    if wc_data.get("exists", False):
        unit = str(wc_data.get("unit", "")).strip().lower()
        if unit == "cm":
            score += 7
            feedback_parts.append("C10(7/7): 'Waist Circumference' category with unit 'cm'")
        else:
            score += 3
            feedback_parts.append(f"C10(3/7): 'Waist Circumference' exists but unit='{wc_data.get('unit')}'")
    else:
        feedback_parts.append("C10(0/7): 'Waist Circumference' NOT found")

    # ------------------------------------------------------------------
    # C11 (7 pts): Resting Heart Rate with unit "bpm"
    # ------------------------------------------------------------------
    rhr_data = measurement_data.get("Resting Heart Rate", {})
    if rhr_data.get("exists", False):
        unit = str(rhr_data.get("unit", "")).strip().lower()
        if unit == "bpm":
            score += 7
            feedback_parts.append("C11(7/7): 'Resting Heart Rate' category with unit 'bpm'")
        else:
            score += 3
            feedback_parts.append(f"C11(3/7): 'Resting Heart Rate' exists but unit='{rhr_data.get('unit')}'")
    else:
        feedback_parts.append("C11(0/7): 'Resting Heart Rate' NOT found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": (
            f"Total: {score}/100 (pass threshold: 70) | "
            + " | ".join(feedback_parts)
        ),
    }
