#!/usr/bin/env python3
"""Verifier for clinical_nutrition_audit task.

Checks that the agent correctly:
1. Corrected 3 nutrition plan energy goals to clinically recommended values
2. Created 2 new measurement tracking categories
3. Created the new corrective nutrition plan

Scoring (100 points total):
  C1 (20 pts): "Cardiac Rehab - Patient A" energy goal corrected to 1800 kcal
  C2 (20 pts): "Diabetes Management - Patient B" energy goal corrected to 2100 kcal
  C3 (20 pts): "Post-Bariatric - Patient C" energy goal corrected to 1400 kcal
  C4 (10 pts): "Resting Heart Rate" measurement category exists with unit "bpm"
  C5 (10 pts): "Blood Glucose" measurement category exists with unit "mg/dL"
  C6 (20 pts): "Renal Nutrition Support - Patient D" nutrition plan exists

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/clinical_nutrition_result.json"


def verify_clinical_nutrition_audit(traj, env_info, task_info):
    """Verify the clinical nutrition audit task completion."""

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

    score = 0
    feedback_parts = []

    # -------------------------------------------------------------------
    # Gate: If ALL energy goals are still at their original wrong values
    # AND no new entities created -> do-nothing, score = 0
    # -------------------------------------------------------------------
    plan_a_energy = result.get("plan_a_current_energy", 0)
    plan_b_energy = result.get("plan_b_current_energy", 0)
    plan_c_energy = result.get("plan_c_current_energy", 0)
    plan_d_exists = result.get("plan_d_exists", False)
    categories = result.get("measurement_categories", {})

    # Convert to float for comparison
    try:
        plan_a_energy = float(plan_a_energy) if plan_a_energy else 0
    except (ValueError, TypeError):
        plan_a_energy = 0
    try:
        plan_b_energy = float(plan_b_energy) if plan_b_energy else 0
    except (ValueError, TypeError):
        plan_b_energy = 0
    try:
        plan_c_energy = float(plan_c_energy) if plan_c_energy else 0
    except (ValueError, TypeError):
        plan_c_energy = 0

    # Check if nothing changed (all still at wrong values)
    a_still_wrong = abs(plan_a_energy - 2800) < 1
    b_still_wrong = abs(plan_b_energy - 3200) < 1
    c_still_wrong = abs(plan_c_energy - 2500) < 1
    no_categories = not any(
        categories.get(c, {}).get("exists", False)
        for c in ["Resting Heart Rate", "Blood Glucose"]
    )
    if a_still_wrong and b_still_wrong and c_still_wrong and no_categories and not plan_d_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: All energy goals remain at their original wrong values "
            "and no new entities were created.",
        }

    # -------------------------------------------------------------------
    # C1 (20 pts): Plan A energy corrected to 1800 kcal
    # -------------------------------------------------------------------
    if abs(plan_a_energy - 1800) < 1:
        score += 20
        feedback_parts.append(
            f"C1(20/20): Cardiac Rehab energy corrected to {plan_a_energy}"
        )
    elif plan_a_energy != 0 and abs(plan_a_energy - 2800) >= 1:
        # Energy was changed from the wrong value but not to the right one
        score += 5
        feedback_parts.append(
            f"C1(5/20): Cardiac Rehab energy changed to {plan_a_energy} "
            f"(expected 1800)"
        )
    else:
        feedback_parts.append(
            f"C1(0/20): Cardiac Rehab energy still at {plan_a_energy} "
            f"(expected 1800)"
        )

    # -------------------------------------------------------------------
    # C2 (20 pts): Plan B energy corrected to 2100 kcal
    # -------------------------------------------------------------------
    if abs(plan_b_energy - 2100) < 1:
        score += 20
        feedback_parts.append(
            f"C2(20/20): Diabetes Mgmt energy corrected to {plan_b_energy}"
        )
    elif plan_b_energy != 0 and abs(plan_b_energy - 3200) >= 1:
        score += 5
        feedback_parts.append(
            f"C2(5/20): Diabetes Mgmt energy changed to {plan_b_energy} "
            f"(expected 2100)"
        )
    else:
        feedback_parts.append(
            f"C2(0/20): Diabetes Mgmt energy still at {plan_b_energy} "
            f"(expected 2100)"
        )

    # -------------------------------------------------------------------
    # C3 (20 pts): Plan C energy corrected to 1400 kcal
    # -------------------------------------------------------------------
    if abs(plan_c_energy - 1400) < 1:
        score += 20
        feedback_parts.append(
            f"C3(20/20): Post-Bariatric energy corrected to {plan_c_energy}"
        )
    elif plan_c_energy != 0 and abs(plan_c_energy - 2500) >= 1:
        score += 5
        feedback_parts.append(
            f"C3(5/20): Post-Bariatric energy changed to {plan_c_energy} "
            f"(expected 1400)"
        )
    else:
        feedback_parts.append(
            f"C3(0/20): Post-Bariatric energy still at {plan_c_energy} "
            f"(expected 1400)"
        )

    # -------------------------------------------------------------------
    # C4 (10 pts): "Resting Heart Rate" measurement category with unit "bpm"
    # -------------------------------------------------------------------
    rhr_data = categories.get("Resting Heart Rate", {})
    if rhr_data.get("exists", False):
        rhr_unit = str(rhr_data.get("unit", "")).strip().lower()
        if rhr_unit == "bpm":
            score += 10
            feedback_parts.append(
                "C4(10/10): 'Resting Heart Rate' category exists with unit 'bpm'"
            )
        else:
            score += 5
            feedback_parts.append(
                f"C4(5/10): 'Resting Heart Rate' exists but unit is "
                f"'{rhr_data.get('unit', '')}' (expected 'bpm')"
            )
    else:
        feedback_parts.append(
            "C4(0/10): 'Resting Heart Rate' measurement category NOT found"
        )

    # -------------------------------------------------------------------
    # C5 (10 pts): "Blood Glucose" measurement category with unit "mg/dL"
    # -------------------------------------------------------------------
    bg_data = categories.get("Blood Glucose", {})
    if bg_data.get("exists", False):
        bg_unit = str(bg_data.get("unit", "")).strip()
        if bg_unit.lower() in ("mg/dl", "mg/dl"):
            score += 10
            feedback_parts.append(
                "C5(10/10): 'Blood Glucose' category exists with unit 'mg/dL'"
            )
        else:
            score += 5
            feedback_parts.append(
                f"C5(5/10): 'Blood Glucose' exists but unit is "
                f"'{bg_data.get('unit', '')}' (expected 'mg/dL')"
            )
    else:
        feedback_parts.append(
            "C5(0/10): 'Blood Glucose' measurement category NOT found"
        )

    # -------------------------------------------------------------------
    # C6 (20 pts): "Renal Nutrition Support - Patient D" plan exists
    # -------------------------------------------------------------------
    if plan_d_exists:
        score += 20
        feedback_parts.append(
            "C6(20/20): 'Renal Nutrition Support - Patient D' nutrition plan exists"
        )
    else:
        feedback_parts.append(
            "C6(0/20): 'Renal Nutrition Support - Patient D' nutrition plan NOT found"
        )

    # -------------------------------------------------------------------
    # Final result
    # -------------------------------------------------------------------
    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": (
            f"Total: {score}/100 (pass threshold: 70) | "
            + " | ".join(feedback_parts)
        ),
    }
