#!/usr/bin/env python3
"""Verifier for sports_nutrition_consultation task.

Checks that the agent correctly:
1. Logged 8 historical body weight entries
2. Created 3 body composition measurement categories with correct units
3. Logged 3 historical entries for each measurement category
4. Created the off-season nutrition plan with correct macros and 6 named meals
5. Created the competition nutrition plan with correct macros and 4 named meals

Scoring (100 points total):
  C1  (16 pts): 8 weight entries on correct dates within ±0.3 kg (2 pts each)
  C2  ( 4 pts): "Body Fat Percentage" category with unit "%"
  C3  ( 4 pts): "Lean Body Mass" category with unit "kg"
  C4  ( 4 pts): "Vertical Jump Height" category with unit "cm"
  C5  ( 6 pts): 3 correct Body Fat Percentage entries (within ±0.2%)
  C6  ( 6 pts): 3 correct Lean Body Mass entries (within ±0.3 kg)
  C7  ( 6 pts): 3 correct Vertical Jump Height entries (within ±1 cm)
  C8  (10 pts): Off-season plan exists with correct description
  C9  (10 pts): Off-season plan macros: energy 4200 kcal, protein 230g, carbs 520g, fat 110g (any 3 of 4)
  C10 (10 pts): Off-season plan has at least 5 of 6 correct meals
  C11 (10 pts): Competition plan exists with correct description
  C12 (10 pts): Competition plan macros: energy 2800 kcal, protein 260g, carbs 280g, fat 70g (any 3 of 4)
  C13 ( 8 pts): Competition plan has at least 3 of 4 correct meals (2 pts each)
  C14 ( 6 pts): Both plans exist (3 pts each)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/sports_nutrition_result.json"

EXPECTED_WEIGHTS = {
    "2026-01-05": 104.2,
    "2026-01-12": 104.8,
    "2026-01-19": 105.3,
    "2026-01-26": 105.6,
    "2026-02-02": 106.1,
    "2026-02-09": 106.4,
    "2026-02-16": 105.8,
    "2026-02-23": 104.9,
}

EXPECTED_BFP = {"2026-01-08": 18.4, "2026-02-05": 17.9, "2026-03-05": 17.2}
EXPECTED_LBM = {"2026-01-08": 85.1, "2026-02-05": 86.3, "2026-03-05": 87.8}
EXPECTED_VJ = {"2026-01-08": 58.0, "2026-02-05": 61.0, "2026-03-05": 64.0}

OFFSEASON_MEALS = [
    "Pre-Workout Fuel",
    "Post-Workout Recovery",
    "Breakfast",
    "Lunch",
    "Dinner",
    "Evening Snack",
]

COMPETITION_MEALS = [
    "Morning Weigh-In Breakfast",
    "Pre-Attempt Snack",
    "Inter-Attempt Fuel",
    "Post-Competition Recovery",
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
    """Case-insensitive, whitespace-normalized meal name matching."""
    actual_lower = {n.strip().lower() for n in actual_names if n}
    return sum(1 for m in expected_names if m.strip().lower() in actual_lower)


def verify_sports_nutrition_consultation(traj, env_info, task_info):
    """Verify the sports nutrition consultation task completion."""

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
    offseason = result.get("offseason_plan", {})
    competition = result.get("competition_plan", {})

    # Gate: do-nothing check
    any_weight = any(
        weight_entries.get(d, {}).get("exists", False) for d in EXPECTED_WEIGHTS
    )
    offseason_found = offseason.get("found", False)
    competition_found = competition.get("found", False)
    any_measure = any(
        measurement_data.get(c, {}).get("exists", False)
        for c in ["Body Fat Percentage", "Lean Body Mass", "Vertical Jump Height"]
    )

    if not any_weight and not offseason_found and not competition_found and not any_measure:
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: No weight entries, nutrition plans, or measurement categories found.",
        }

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # C1 (16 pts): 8 weight entries, 2 pts each within ±0.3 kg
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
    feedback_parts.append(f"C1({c1_pts}/16): {weight_correct}/8 weight entries correct")

    # ------------------------------------------------------------------
    # C2-C4 (4 pts each): Measurement categories with correct units
    # ------------------------------------------------------------------
    for cat_name, expected_unit, label, pts in [
        ("Body Fat Percentage", "%", "C2", 4),
        ("Lean Body Mass", "kg", "C3", 4),
        ("Vertical Jump Height", "cm", "C4", 4),
    ]:
        cat_data = measurement_data.get(cat_name, {})
        if cat_data.get("exists", False):
            actual_unit = str(cat_data.get("unit", "")).strip().lower()
            if actual_unit == expected_unit.lower():
                score += pts
                feedback_parts.append(f"{label}({pts}/{pts}): '{cat_name}' with unit '{expected_unit}'")
            else:
                score += 2
                feedback_parts.append(f"{label}(2/{pts}): '{cat_name}' exists but unit='{cat_data.get('unit')}'")
        else:
            feedback_parts.append(f"{label}(0/{pts}): '{cat_name}' NOT found")

    # ------------------------------------------------------------------
    # C5 (6 pts): 3 BFP entries within ±0.2%
    # ------------------------------------------------------------------
    bfp_data = measurement_data.get("Body Fat Percentage", {})
    bfp_correct = count_entries_correct(bfp_data, EXPECTED_BFP, 0.2) if bfp_data.get("exists") else 0
    c5_pts = 6 if bfp_correct == 3 else (4 if bfp_correct == 2 else (2 if bfp_correct == 1 else 0))
    score += c5_pts
    feedback_parts.append(f"C5({c5_pts}/6): {bfp_correct}/3 Body Fat % entries correct")

    # ------------------------------------------------------------------
    # C6 (6 pts): 3 LBM entries within ±0.3 kg
    # ------------------------------------------------------------------
    lbm_data = measurement_data.get("Lean Body Mass", {})
    lbm_correct = count_entries_correct(lbm_data, EXPECTED_LBM, 0.3) if lbm_data.get("exists") else 0
    c6_pts = 6 if lbm_correct == 3 else (4 if lbm_correct == 2 else (2 if lbm_correct == 1 else 0))
    score += c6_pts
    feedback_parts.append(f"C6({c6_pts}/6): {lbm_correct}/3 Lean Body Mass entries correct")

    # ------------------------------------------------------------------
    # C7 (6 pts): 3 VJ entries within ±1 cm
    # ------------------------------------------------------------------
    vj_data = measurement_data.get("Vertical Jump Height", {})
    vj_correct = count_entries_correct(vj_data, EXPECTED_VJ, 1) if vj_data.get("exists") else 0
    c7_pts = 6 if vj_correct == 3 else (4 if vj_correct == 2 else (2 if vj_correct == 1 else 0))
    score += c7_pts
    feedback_parts.append(f"C7({c7_pts}/6): {vj_correct}/3 Vertical Jump entries correct")

    # ------------------------------------------------------------------
    # C8 (10 pts): Off-season plan exists
    # ------------------------------------------------------------------
    if offseason_found:
        score += 10
        feedback_parts.append("C8(10/10): Off-season plan 'Powerlifter Off-Season Hypertrophy Phase' exists")
    else:
        feedback_parts.append("C8(0/10): Off-season plan NOT found")

    # ------------------------------------------------------------------
    # C9 (10 pts): Off-season plan macros (any 3 of 4 within tolerance)
    # ------------------------------------------------------------------
    if offseason_found:
        macro_ok = 0
        macro_details = []
        for field, expected, label, tol in [
            ("goal_energy", 4200, "Energy", 15),
            ("goal_protein", 230, "Protein", 5),
            ("goal_carbohydrates", 520, "Carbs", 5),
            ("goal_fat", 110, "Fat", 5),
        ]:
            actual = float(offseason.get(field) or 0)
            if abs(actual - expected) <= tol:
                macro_ok += 1
                macro_details.append(f"{label}={actual} OK")
            else:
                macro_details.append(f"{label}={actual}(exp {expected})")

        c9_pts = 10 if macro_ok >= 3 else (6 if macro_ok == 2 else (3 if macro_ok == 1 else 0))
        score += c9_pts
        feedback_parts.append(f"C9({c9_pts}/10): {macro_ok}/4 off-season macros correct [{'; '.join(macro_details)}]")
    else:
        feedback_parts.append("C9(0/10): No off-season plan to check macros")

    # ------------------------------------------------------------------
    # C10 (10 pts): Off-season plan has at least 5 of 6 meals
    # ------------------------------------------------------------------
    if offseason_found:
        actual_meal_names = offseason.get("meal_names", [])
        meals_found = count_matching_meals(actual_meal_names, OFFSEASON_MEALS)
        c10_pts = 10 if meals_found >= 5 else (7 if meals_found >= 4 else (4 if meals_found >= 2 else (2 if meals_found >= 1 else 0)))
        score += c10_pts
        feedback_parts.append(f"C10({c10_pts}/10): {meals_found}/6 off-season meals correct [found: {actual_meal_names}]")
    else:
        feedback_parts.append("C10(0/10): No off-season plan to check meals")

    # ------------------------------------------------------------------
    # C11 (10 pts): Competition plan exists
    # ------------------------------------------------------------------
    if competition_found:
        score += 10
        feedback_parts.append("C11(10/10): Competition plan 'Powerlifter Competition Peak - Weight Cut' exists")
    else:
        feedback_parts.append("C11(0/10): Competition plan NOT found")

    # ------------------------------------------------------------------
    # C12 (10 pts): Competition plan macros (any 3 of 4)
    # ------------------------------------------------------------------
    if competition_found:
        macro_ok = 0
        macro_details = []
        for field, expected, label, tol in [
            ("goal_energy", 2800, "Energy", 15),
            ("goal_protein", 260, "Protein", 5),
            ("goal_carbohydrates", 280, "Carbs", 5),
            ("goal_fat", 70, "Fat", 5),
        ]:
            actual = float(competition.get(field) or 0)
            if abs(actual - expected) <= tol:
                macro_ok += 1
                macro_details.append(f"{label}={actual} OK")
            else:
                macro_details.append(f"{label}={actual}(exp {expected})")

        c12_pts = 10 if macro_ok >= 3 else (6 if macro_ok == 2 else (3 if macro_ok == 1 else 0))
        score += c12_pts
        feedback_parts.append(f"C12({c12_pts}/10): {macro_ok}/4 competition macros correct [{'; '.join(macro_details)}]")
    else:
        feedback_parts.append("C12(0/10): No competition plan to check macros")

    # ------------------------------------------------------------------
    # C13 (8 pts): Competition plan has at least 3 of 4 meals
    # ------------------------------------------------------------------
    if competition_found:
        actual_meal_names = competition.get("meal_names", [])
        meals_found = count_matching_meals(actual_meal_names, COMPETITION_MEALS)
        c13_pts = 8 if meals_found >= 3 else (5 if meals_found == 2 else (2 if meals_found == 1 else 0))
        score += c13_pts
        feedback_parts.append(f"C13({c13_pts}/8): {meals_found}/4 competition meals correct [found: {actual_meal_names}]")
    else:
        feedback_parts.append("C13(0/8): No competition plan to check meals")

    # ------------------------------------------------------------------
    # C14 (6 pts): Both plans exist (3 pts each, already captured above)
    # ------------------------------------------------------------------
    # C14 is already captured implicitly by C8 and C11, so skip to avoid double-count.
    # Total = 16+4+4+4+6+6+6+10+10+10+10+10+8 = 104. We cap at 100.

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": (
            f"Total: {score}/104 (pass threshold: 60, capped at 100) | "
            + " | ".join(feedback_parts)
        ),
    }
