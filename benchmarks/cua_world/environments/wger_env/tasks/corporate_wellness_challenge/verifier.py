#!/usr/bin/env python3
"""Verifier for corporate_wellness_challenge task.

Checks that the agent correctly:
1. Created 3 employee user accounts with correct details
2. Created 3 personalized workout routines
3. Created the BMI measurement category
4. Created the team nutrition plan

Scoring (100 points total):
  C1 (15 pts): maria_chen user exists with correct first/last/email
  C2 (15 pts): david_okonkwo user exists with correct first/last/email
  C3 (15 pts): sarah_patel user exists with correct first/last/email
  C4 (10 pts): "Cardio Kickstart - Maria" routine exists
  C5 (10 pts): "Strength Foundations - David" routine exists
  C6 (10 pts): "Flexibility & Recovery - Sarah" routine exists
  C7 (10 pts): "BMI" measurement category exists with unit "index"
  C8 (15 pts): "Apex Wellness Q1 Team Plan" nutrition plan exists

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/corporate_wellness_result.json"


def _check_user(users_data, username, expected_first, expected_last, expected_email):
    """Check a single user account and return (points, feedback_str).

    Awards up to 15 points:
      - 5 pts for user existing
      - 4 pts for correct first name (case-insensitive)
      - 3 pts for correct last name (case-insensitive)
      - 3 pts for correct email (case-insensitive)
    """
    user_info = users_data.get(username, {})
    if not user_info.get("exists", False):
        return 0, f"{username}: user does not exist"

    pts = 5  # user exists
    parts = [f"{username}: exists"]

    actual_first = user_info.get("first_name", "")
    if actual_first.strip().lower() == expected_first.lower():
        pts += 4
        parts.append(f"first_name OK")
    else:
        parts.append(f"first_name MISMATCH (got '{actual_first}', expected '{expected_first}')")

    actual_last = user_info.get("last_name", "")
    if actual_last.strip().lower() == expected_last.lower():
        pts += 3
        parts.append(f"last_name OK")
    else:
        parts.append(f"last_name MISMATCH (got '{actual_last}', expected '{expected_last}')")

    actual_email = user_info.get("email", "")
    if actual_email.strip().lower() == expected_email.lower():
        pts += 3
        parts.append(f"email OK")
    else:
        parts.append(f"email MISMATCH (got '{actual_email}', expected '{expected_email}')")

    return pts, " | ".join(parts)


def verify_corporate_wellness_challenge(traj, env_info, task_info):
    """Verify the corporate wellness challenge task completion."""

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

    users_data = result.get("users", {})
    routines_data = result.get("routines", {})
    bmi_data = result.get("measurement_category_bmi", {})
    plan_data = result.get("nutrition_plan", {})

    # -------------------------------------------------------------------
    # Gate: If NO users were created at all, score = 0
    # -------------------------------------------------------------------
    any_user_exists = any(
        users_data.get(u, {}).get("exists", False)
        for u in ["maria_chen", "david_okonkwo", "sarah_patel"]
    )
    if not any_user_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Gate failed: none of the 3 required employee accounts were created.",
        }

    score = 0
    feedback_parts = []

    # -------------------------------------------------------------------
    # C1 (15 pts): maria_chen
    # -------------------------------------------------------------------
    pts, fb = _check_user(users_data, "maria_chen", "Maria", "Chen", "maria.chen@apexmfg.com")
    score += pts
    feedback_parts.append(f"C1({pts}/15): {fb}")

    # -------------------------------------------------------------------
    # C2 (15 pts): david_okonkwo
    # -------------------------------------------------------------------
    pts, fb = _check_user(users_data, "david_okonkwo", "David", "Okonkwo", "david.okonkwo@apexmfg.com")
    score += pts
    feedback_parts.append(f"C2({pts}/15): {fb}")

    # -------------------------------------------------------------------
    # C3 (15 pts): sarah_patel
    # -------------------------------------------------------------------
    pts, fb = _check_user(users_data, "sarah_patel", "Sarah", "Patel", "sarah.patel@apexmfg.com")
    score += pts
    feedback_parts.append(f"C3({pts}/15): {fb}")

    # -------------------------------------------------------------------
    # C4 (10 pts): "Cardio Kickstart - Maria" routine
    # -------------------------------------------------------------------
    routine_maria = routines_data.get("Cardio Kickstart - Maria", {})
    if routine_maria.get("exists", False):
        score += 10
        feedback_parts.append("C4(10/10): 'Cardio Kickstart - Maria' routine exists")
    else:
        feedback_parts.append("C4(0/10): 'Cardio Kickstart - Maria' routine NOT found")

    # -------------------------------------------------------------------
    # C5 (10 pts): "Strength Foundations - David" routine
    # -------------------------------------------------------------------
    routine_david = routines_data.get("Strength Foundations - David", {})
    if routine_david.get("exists", False):
        score += 10
        feedback_parts.append("C5(10/10): 'Strength Foundations - David' routine exists")
    else:
        feedback_parts.append("C5(0/10): 'Strength Foundations - David' routine NOT found")

    # -------------------------------------------------------------------
    # C6 (10 pts): "Flexibility & Recovery - Sarah" routine
    # -------------------------------------------------------------------
    routine_sarah = routines_data.get("Flexibility & Recovery - Sarah", {})
    if routine_sarah.get("exists", False):
        score += 10
        feedback_parts.append("C6(10/10): 'Flexibility & Recovery - Sarah' routine exists")
    else:
        feedback_parts.append("C6(0/10): 'Flexibility & Recovery - Sarah' routine NOT found")

    # -------------------------------------------------------------------
    # C7 (10 pts): "BMI" measurement category with unit "index"
    # -------------------------------------------------------------------
    if bmi_data.get("exists", False):
        bmi_unit = str(bmi_data.get("unit", "")).strip().lower()
        if bmi_unit == "index":
            score += 10
            feedback_parts.append("C7(10/10): 'BMI' measurement category exists with unit 'index'")
        else:
            # Category exists but unit is wrong — partial credit
            score += 5
            feedback_parts.append(
                f"C7(5/10): 'BMI' measurement category exists but unit is '{bmi_data.get('unit', '')}' (expected 'index')"
            )
    else:
        feedback_parts.append("C7(0/10): 'BMI' measurement category NOT found")

    # -------------------------------------------------------------------
    # C8 (15 pts): "Apex Wellness Q1 Team Plan" nutrition plan
    # -------------------------------------------------------------------
    if plan_data.get("exists", False):
        score += 15
        feedback_parts.append("C8(15/15): 'Apex Wellness Q1 Team Plan' nutrition plan exists")
    else:
        feedback_parts.append("C8(0/15): 'Apex Wellness Q1 Team Plan' nutrition plan NOT found")

    # -------------------------------------------------------------------
    # Final result
    # -------------------------------------------------------------------
    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": f"Total: {score}/100 (pass threshold: 70) | " + " | ".join(feedback_parts),
    }
