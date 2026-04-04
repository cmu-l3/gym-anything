#!/usr/bin/env python3
"""Verifier for research_cohort_fitness_baseline task.

Checks that the agent correctly:
1. Registered 4 research participants as wger users with correct credentials
2. Created 3 standardized fitness measurement categories with correct units
3. Logged 4 baseline measurements per category (one per participant)
4. Built the STRIDE-26 exercise intervention routine with 3 training days (correct DOW) and exercises
5. Created the standardized dietary reference nutrition plan with correct macros and 4 meal slots

Scoring (100 points total):
  C1  (20 pts): 4 participants registered with correct usernames (5 pts each)
  C2  ( 8 pts): 4 participants have correct email addresses (2 pts each)
  C3  ( 4 pts): "VO2max Estimate" category with unit "ml/kg/min"
  C4  ( 4 pts): "Handgrip Strength" category with unit "kg"
  C5  ( 4 pts): "Single-Leg Balance Time" category with unit "s"
  C6  ( 8 pts): 4 correct VO2max baseline entries (within ±0.5 ml/kg/min)
  C7  ( 8 pts): 4 correct Handgrip baseline entries (within ±0.5 kg)
  C8  ( 8 pts): 4 correct Single-Leg Balance entries (within ±1 s)
  C9  (10 pts): "STRIDE-26 Standardized Exercise Intervention" routine with correct description
  C10 ( 9 pts): All 3 named training days exist (3 pts each)
  C11 ( 6 pts): At least 2 days have correct day-of-week assignment (3 pts each)
  C12 ( 3 pts): At least 3 exercises assigned across all training days
  C13 ( 8 pts): "STRIDE-26 Standardized Dietary Reference" nutrition plan with correct macros (any 3 of 4)
  C14 ( 8 pts): All 4 meal slots created in nutrition plan

Pass threshold: 70 points

Anti-pattern 4 check:
  Max score WITHOUT entries (C6-C8=0), macros (C13=0), meals (C14=0):
    C1(20)+C2(8)+C3(4)+C4(4)+C5(4)+C9(10)+C10(9)+C11(6)+C12(3) = 68 < 70 ✓
  Agent must complete at least measurement entries, macros, or meals to pass.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/research_cohort_result.json"

EXPECTED_USERS = [
    {"username": "stride26_p001", "email": "participant001@stride26study.org"},
    {"username": "stride26_p002", "email": "participant002@stride26study.org"},
    {"username": "stride26_p003", "email": "participant003@stride26study.org"},
    {"username": "stride26_p004", "email": "participant004@stride26study.org"},
]

EXPECTED_VO2MAX = {
    "2026-02-02": 34.2,
    "2026-02-03": 41.8,
    "2026-02-04": 28.9,
    "2026-02-05": 38.5,
}

EXPECTED_GRIP = {
    "2026-02-02": 32.4,
    "2026-02-03": 38.1,
    "2026-02-04": 29.6,
    "2026-02-05": 35.8,
}

EXPECTED_BALANCE = {
    "2026-02-02": 18.0,
    "2026-02-03": 24.0,
    "2026-02-04": 12.0,
    "2026-02-05": 21.0,
}

EXPECTED_DAY_NAMES = {
    "Aerobic Conditioning": 2,          # Tuesday
    "Functional Strength Training": 4,  # Thursday
    "Active Mobility Session": 6,       # Saturday
}

EXPECTED_MEALS = [
    "Standardized Breakfast",
    "Standardized Lunch",
    "Standardized Dinner",
    "Post-Exercise Recovery",
]


def count_entries_correct(data_dict, expected_dict, tolerance):
    correct = 0
    entries = data_dict.get("entries", {})
    for date_str, expected_val in expected_dict.items():
        actual = entries.get(date_str)
        if actual is not None and abs(float(actual) - expected_val) <= tolerance:
            correct += 1
    return correct


def count_matching_meals(actual_names, expected_names):
    actual_lower = {n.strip().lower() for n in actual_names if n}
    return sum(1 for m in expected_names if m.strip().lower() in actual_lower)


def verify_research_cohort_fitness_baseline(traj, env_info, task_info):
    """Verify the research cohort fitness baseline task completion."""

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
    measurement_data = result.get("measurement_data", {})
    routine_data = result.get("routine", {})
    plan_data = result.get("nutrition_plan", {})

    # Gate: do-nothing check
    any_user = any(users_data.get(u["username"], {}).get("exists", False) for u in EXPECTED_USERS)
    routine_found = routine_data.get("found", False)
    plan_found = plan_data.get("found", False)
    any_measure = any(
        measurement_data.get(c, {}).get("exists", False)
        for c in ["VO2max Estimate", "Handgrip Strength", "Single-Leg Balance Time"]
    )

    if not any_user and not routine_found and not plan_found and not any_measure:
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: No participants registered, routine, measurement categories, or nutrition plan found.",
        }

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # C1 (20 pts): 4 participants registered (5 pts each)
    # ------------------------------------------------------------------
    users_registered = sum(
        1 for eu in EXPECTED_USERS
        if users_data.get(eu["username"], {}).get("exists", False)
    )
    c1_pts = users_registered * 5
    score += c1_pts
    feedback_parts.append(f"C1({c1_pts}/20): {users_registered}/4 participants registered")

    # ------------------------------------------------------------------
    # C2 (8 pts): Correct email addresses (2 pts each)
    # ------------------------------------------------------------------
    emails_correct = sum(
        1 for eu in EXPECTED_USERS
        if users_data.get(eu["username"], {}).get("exists", False)
        and users_data.get(eu["username"], {}).get("email_correct", False)
    )
    c2_pts = emails_correct * 2
    score += c2_pts
    feedback_parts.append(f"C2({c2_pts}/8): {emails_correct}/4 participants have correct email")

    # ------------------------------------------------------------------
    # C3-C5 (4 pts each): Measurement categories with correct units
    # ------------------------------------------------------------------
    cat_specs = [
        ("VO2max Estimate", "ml/kg/min", "C3"),
        ("Handgrip Strength", "kg", "C4"),
        ("Single-Leg Balance Time", "s", "C5"),
    ]
    for cat_name, expected_unit, label in cat_specs:
        cat_data = measurement_data.get(cat_name, {})
        if cat_data.get("exists", False):
            actual_unit = str(cat_data.get("unit", "")).strip().lower()
            if actual_unit == expected_unit.lower():
                score += 4
                feedback_parts.append(f"{label}(4/4): '{cat_name}' with unit '{expected_unit}'")
            else:
                score += 2
                feedback_parts.append(f"{label}(2/4): '{cat_name}' exists but unit='{cat_data.get('unit')}'")
        else:
            feedback_parts.append(f"{label}(0/4): '{cat_name}' NOT found")

    # ------------------------------------------------------------------
    # C6-C8 (8 pts each): 4 correct measurement entries per category
    # ------------------------------------------------------------------
    measurement_specs = [
        ("VO2max Estimate", EXPECTED_VO2MAX, 0.5, "C6"),
        ("Handgrip Strength", EXPECTED_GRIP, 0.5, "C7"),
        ("Single-Leg Balance Time", EXPECTED_BALANCE, 1.0, "C8"),
    ]
    for cat_name, expected_dict, tolerance, label in measurement_specs:
        cat_data = measurement_data.get(cat_name, {})
        correct = count_entries_correct(cat_data, expected_dict, tolerance) if cat_data.get("exists") else 0
        pts = 8 if correct == 4 else (6 if correct == 3 else (4 if correct == 2 else (2 if correct == 1 else 0)))
        score += pts
        feedback_parts.append(f"{label}({pts}/8): {correct}/4 {cat_name} entries correct")

    # ------------------------------------------------------------------
    # C9 (10 pts): Routine exists with correct description
    # ------------------------------------------------------------------
    if routine_found:
        desc = (routine_data.get("description") or "").strip()
        expected_desc = "52-week workplace fitness RCT: progressive moderate-intensity aerobic and functional strength protocol"
        if expected_desc.lower() in desc.lower() or desc.lower() in expected_desc.lower():
            score += 10
            feedback_parts.append("C9(10/10): Routine exists with correct description")
        else:
            score += 4
            feedback_parts.append(f"C9(4/10): Routine exists but description mismatch: '{desc[:80]}'")
    else:
        feedback_parts.append("C9(0/10): 'STRIDE-26 Standardized Exercise Intervention' routine NOT found")

    # ------------------------------------------------------------------
    # C10 (9 pts): All 3 named training days exist (3 pts each)
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

    c10_pts = days_found_count * 3
    score += c10_pts
    feedback_parts.append(f"C10({c10_pts}/9): {days_found_count}/3 training days found")

    # ------------------------------------------------------------------
    # C11 (6 pts): At least 2 days have correct DOW (3 pts each)
    # ------------------------------------------------------------------
    c11_pts = min(correct_dow_count * 3, 6)
    score += c11_pts
    feedback_parts.append(f"C11({c11_pts}/6): {correct_dow_count}/3 days have correct day-of-week")

    # ------------------------------------------------------------------
    # C12 (3 pts): At least 3 exercises assigned
    # ------------------------------------------------------------------
    total_exercises = sum(len(d.get("exercises", [])) for d in days)
    if total_exercises >= 4:
        score += 3
        feedback_parts.append(f"C12(3/3): {total_exercises} exercises assigned")
    elif total_exercises >= 3:
        score += 2
        feedback_parts.append(f"C12(2/3): {total_exercises} exercises assigned")
    elif total_exercises >= 1:
        score += 1
        feedback_parts.append(f"C12(1/3): {total_exercises} exercises assigned")
    else:
        feedback_parts.append("C12(0/3): No exercises assigned")

    # ------------------------------------------------------------------
    # C13 (8 pts): Nutrition plan macros (any 3 of 4)
    # ------------------------------------------------------------------
    if plan_found:
        macro_ok = 0
        macro_details = []
        for field, expected, label, tol in [
            ("goal_energy", 2400, "Energy", 15),
            ("goal_protein", 120, "Protein", 5),
            ("goal_carbohydrates", 310, "Carbs", 5),
            ("goal_fat", 72, "Fat", 5),
        ]:
            actual = float(plan_data.get(field) or 0)
            if abs(actual - expected) <= tol:
                macro_ok += 1
                macro_details.append(f"{label}={actual} OK")
            else:
                macro_details.append(f"{label}={actual}(exp {expected})")

        c13_pts = 8 if macro_ok >= 3 else (5 if macro_ok == 2 else (2 if macro_ok == 1 else 0))
        score += c13_pts
        feedback_parts.append(f"C13({c13_pts}/8): {macro_ok}/4 macros correct [{'; '.join(macro_details)}]")
    else:
        feedback_parts.append("C13(0/8): 'STRIDE-26 Standardized Dietary Reference' nutrition plan NOT found")

    # ------------------------------------------------------------------
    # C14 (8 pts): All 4 meal slots in nutrition plan
    # ------------------------------------------------------------------
    if plan_found:
        actual_meal_names = plan_data.get("meal_names", [])
        meals_found = count_matching_meals(actual_meal_names, EXPECTED_MEALS)
        c14_pts = 8 if meals_found == 4 else (6 if meals_found == 3 else (4 if meals_found == 2 else (2 if meals_found == 1 else 0)))
        score += c14_pts
        feedback_parts.append(f"C14({c14_pts}/8): {meals_found}/4 meal slots correct [found: {actual_meal_names}]")
    else:
        feedback_parts.append("C14(0/8): No plan to check meals")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": (
            f"Total: {score}/100 (pass threshold: 70) | "
            + " | ".join(feedback_parts)
        ),
    }
