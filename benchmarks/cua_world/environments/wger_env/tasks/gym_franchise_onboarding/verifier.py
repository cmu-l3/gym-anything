#!/usr/bin/env python3
"""Verifier for gym_franchise_onboarding task.

Checks that the agent correctly completed the full franchise onboarding:
1. Registered 4 staff/member accounts with correct details
2. Created the "New Member Welcome Routine" with correct description
3. Added 3 training days with correct names and day-of-week assignments
4. Created the "30-Day Transformation Kickstart" nutrition plan
5. Created 2 measurement categories with correct units

Scoring (100 points total):
  C1  (10 pts): coach_rivera user exists with correct first/last/email
  C2  (10 pts): coach_nakamura user exists with correct first/last/email
  C3  (10 pts): front_desk_jones user exists with correct first/last/email
  C4  (10 pts): member_williams user exists with correct first/last/email
  C5  (10 pts): "New Member Welcome Routine" exists with correct description
  C6  ( 5 pts): "Full Body Intro" training day exists under the routine
  C7  ( 5 pts): "Upper Body Focus" training day exists under the routine
  C8  ( 5 pts): "Lower Body & Core" training day exists under the routine
  C9  ( 5 pts): At least 2 training days have correct day-of-week assignments
  C10 (10 pts): "30-Day Transformation Kickstart" nutrition plan exists
  C11 (10 pts): "Body Fat Percentage" measurement category exists with unit "%"
  C12 (10 pts): "Lean Muscle Mass" measurement category exists with unit "kg"

Pass threshold: 65 points
Gate: If zero of the 4 users exist AND routine does not exist -> score = 0
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/gym_franchise_result.json"

# Day-of-week mapping in wger: 1=Monday, 2=Tuesday, 3=Wednesday,
# 4=Thursday, 5=Friday, 6=Saturday, 7=Sunday
EXPECTED_DAYS = {
    "Full Body Intro": 1,       # Monday
    "Upper Body Focus": 3,      # Wednesday
    "Lower Body & Core": 5,     # Friday
}


def _check_user(users_data, username, expected_first, expected_last, expected_email):
    """Check a single user account and return (points, feedback_str).

    Awards up to 10 points:
      - 4 pts for user existing
      - 2 pts for correct first name (case-insensitive)
      - 2 pts for correct last name (case-insensitive)
      - 2 pts for correct email (case-insensitive)
    """
    user_info = users_data.get(username, {})
    if not user_info.get("exists", False):
        return 0, f"{username}: user does not exist"

    pts = 4  # user exists
    parts = [f"{username}: exists"]

    actual_first = user_info.get("first_name", "")
    if actual_first.strip().lower() == expected_first.lower():
        pts += 2
        parts.append("first_name OK")
    else:
        parts.append(
            f"first_name MISMATCH (got '{actual_first}', expected '{expected_first}')"
        )

    actual_last = user_info.get("last_name", "")
    if actual_last.strip().lower() == expected_last.lower():
        pts += 2
        parts.append("last_name OK")
    else:
        parts.append(
            f"last_name MISMATCH (got '{actual_last}', expected '{expected_last}')"
        )

    actual_email = user_info.get("email", "")
    if actual_email.strip().lower() == expected_email.lower():
        pts += 2
        parts.append("email OK")
    else:
        parts.append(
            f"email MISMATCH (got '{actual_email}', expected '{expected_email}')"
        )

    return pts, " | ".join(parts)


def verify_gym_franchise_onboarding(traj, env_info, task_info):
    """Verify the gym franchise onboarding task completion."""

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
    routine_data = result.get("routine", {})
    plan_data = result.get("nutrition_plan", {})
    categories_data = result.get("measurement_categories", {})

    # -------------------------------------------------------------------
    # Gate: If NO users were created AND routine doesn't exist -> score = 0
    # -------------------------------------------------------------------
    any_user_exists = any(
        users_data.get(u, {}).get("exists", False)
        for u in [
            "coach_rivera",
            "coach_nakamura",
            "front_desk_jones",
            "member_williams",
        ]
    )
    routine_exists = routine_data.get("found", False)

    if not any_user_exists and not routine_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Gate failed: none of the 4 required accounts were created "
            "AND the routine does not exist. No meaningful work detected.",
        }

    score = 0
    feedback_parts = []

    # -------------------------------------------------------------------
    # C1 (10 pts): coach_rivera
    # -------------------------------------------------------------------
    pts, fb = _check_user(
        users_data,
        "coach_rivera",
        "Carlos",
        "Rivera",
        "carlos.rivera@ironpeakfit.com",
    )
    score += pts
    feedback_parts.append(f"C1({pts}/10): {fb}")

    # -------------------------------------------------------------------
    # C2 (10 pts): coach_nakamura
    # -------------------------------------------------------------------
    pts, fb = _check_user(
        users_data,
        "coach_nakamura",
        "Yuki",
        "Nakamura",
        "yuki.nakamura@ironpeakfit.com",
    )
    score += pts
    feedback_parts.append(f"C2({pts}/10): {fb}")

    # -------------------------------------------------------------------
    # C3 (10 pts): front_desk_jones
    # -------------------------------------------------------------------
    pts, fb = _check_user(
        users_data,
        "front_desk_jones",
        "Tamika",
        "Jones",
        "tamika.jones@ironpeakfit.com",
    )
    score += pts
    feedback_parts.append(f"C3({pts}/10): {fb}")

    # -------------------------------------------------------------------
    # C4 (10 pts): member_williams
    # -------------------------------------------------------------------
    pts, fb = _check_user(
        users_data,
        "member_williams",
        "Derek",
        "Williams",
        "derek.williams@ironpeakfit.com",
    )
    score += pts
    feedback_parts.append(f"C4({pts}/10): {fb}")

    # -------------------------------------------------------------------
    # C5 (10 pts): "New Member Welcome Routine" exists with correct description
    # -------------------------------------------------------------------
    if routine_exists:
        actual_desc = routine_data.get("description", "").strip()
        expected_desc = (
            "Standard 4-week introductory program for all new Iron Peak Fitness members"
        )
        if actual_desc.lower() == expected_desc.lower():
            score += 10
            feedback_parts.append(
                "C5(10/10): 'New Member Welcome Routine' exists with correct description"
            )
        else:
            # Routine exists but description doesn't match — partial credit
            score += 5
            feedback_parts.append(
                f"C5(5/10): 'New Member Welcome Routine' exists but description "
                f"mismatch (got '{actual_desc[:80]}...')"
            )
    else:
        feedback_parts.append(
            "C5(0/10): 'New Member Welcome Routine' NOT found"
        )

    # -------------------------------------------------------------------
    # C6-C8 (5 pts each): Training days exist under the routine
    # C9 (5 pts): At least 2 days have correct day-of-week assignments
    # -------------------------------------------------------------------
    days = routine_data.get("days", [])
    day_names_found = {d.get("name", "").strip(): d for d in days}

    correct_dow_count = 0

    # C6: "Full Body Intro"
    if "Full Body Intro" in day_names_found:
        score += 5
        feedback_parts.append(
            "C6(5/5): 'Full Body Intro' training day exists"
        )
        dow_list = day_names_found["Full Body Intro"].get("day_of_week", [])
        if EXPECTED_DAYS["Full Body Intro"] in dow_list:
            correct_dow_count += 1
    else:
        feedback_parts.append(
            "C6(0/5): 'Full Body Intro' training day NOT found"
        )

    # C7: "Upper Body Focus"
    if "Upper Body Focus" in day_names_found:
        score += 5
        feedback_parts.append(
            "C7(5/5): 'Upper Body Focus' training day exists"
        )
        dow_list = day_names_found["Upper Body Focus"].get("day_of_week", [])
        if EXPECTED_DAYS["Upper Body Focus"] in dow_list:
            correct_dow_count += 1
    else:
        feedback_parts.append(
            "C7(0/5): 'Upper Body Focus' training day NOT found"
        )

    # C8: "Lower Body & Core"
    if "Lower Body & Core" in day_names_found:
        score += 5
        feedback_parts.append(
            "C8(5/5): 'Lower Body & Core' training day exists"
        )
        dow_list = day_names_found["Lower Body & Core"].get("day_of_week", [])
        if EXPECTED_DAYS["Lower Body & Core"] in dow_list:
            correct_dow_count += 1
    else:
        feedback_parts.append(
            "C8(0/5): 'Lower Body & Core' training day NOT found"
        )

    # C9: At least 2 days have correct day-of-week
    if correct_dow_count >= 2:
        score += 5
        feedback_parts.append(
            f"C9(5/5): {correct_dow_count}/3 training days have correct day-of-week"
        )
    else:
        feedback_parts.append(
            f"C9(0/5): Only {correct_dow_count}/3 training days have correct "
            f"day-of-week (need >= 2)"
        )

    # -------------------------------------------------------------------
    # C10 (10 pts): "30-Day Transformation Kickstart" nutrition plan exists
    # -------------------------------------------------------------------
    if plan_data.get("found", False):
        score += 10
        feedback_parts.append(
            "C10(10/10): '30-Day Transformation Kickstart' nutrition plan exists"
        )
    else:
        feedback_parts.append(
            "C10(0/10): '30-Day Transformation Kickstart' nutrition plan NOT found"
        )

    # -------------------------------------------------------------------
    # C11 (10 pts): "Body Fat Percentage" category exists with unit "%"
    # -------------------------------------------------------------------
    bf_data = categories_data.get("Body Fat Percentage", {})
    if bf_data.get("exists", False):
        bf_unit = str(bf_data.get("unit", "")).strip()
        if bf_unit == "%":
            score += 10
            feedback_parts.append(
                "C11(10/10): 'Body Fat Percentage' category exists with unit '%'"
            )
        else:
            # Category exists but unit is wrong — partial credit
            score += 5
            feedback_parts.append(
                f"C11(5/10): 'Body Fat Percentage' category exists but unit is "
                f"'{bf_unit}' (expected '%')"
            )
    else:
        feedback_parts.append(
            "C11(0/10): 'Body Fat Percentage' measurement category NOT found"
        )

    # -------------------------------------------------------------------
    # C12 (10 pts): "Lean Muscle Mass" category exists with unit "kg"
    # -------------------------------------------------------------------
    lm_data = categories_data.get("Lean Muscle Mass", {})
    if lm_data.get("exists", False):
        lm_unit = str(lm_data.get("unit", "")).strip().lower()
        if lm_unit == "kg":
            score += 10
            feedback_parts.append(
                "C12(10/10): 'Lean Muscle Mass' category exists with unit 'kg'"
            )
        else:
            # Category exists but unit is wrong — partial credit
            score += 5
            feedback_parts.append(
                f"C12(5/10): 'Lean Muscle Mass' category exists but unit is "
                f"'{lm_data.get('unit', '')}' (expected 'kg')"
            )
    else:
        feedback_parts.append(
            "C12(0/10): 'Lean Muscle Mass' measurement category NOT found"
        )

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
