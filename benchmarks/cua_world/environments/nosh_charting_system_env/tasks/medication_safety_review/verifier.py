#!/usr/bin/env python3
"""
Verifier for medication_safety_review task.

Patient: Cordie King (pid=13, DOB: 1995-03-11)
Scenario: Medication safety review for a patient on anticoagulation therapy.
Setup seeds (contamination-injection pattern):
  - Warfarin 5mg daily (active - must remain active)
  - Aspirin 325mg daily (active - must be discontinued: antiplatelet + Warfarin = bleeding risk)
  - Ibuprofen 600mg TID (active - must be discontinued: NSAID + Warfarin = bleeding risk)

Scoring (designed to prevent gaming by mass-discontinuation):
  1. Aspirin discontinued (25 pts)
  2. Ibuprofen discontinued (25 pts)
  3. Warfarin still active / NOT discontinued (30 pts) - critical anti-gaming criterion
     If Warfarin is wrongly discontinued, max score without it = 25+25+10+10 = 70, below threshold 75
  4. INR lab ordered (10 pts)
  5. Encounter created (10 pts)

Total: 100 pts
Pass threshold: 75 pts

Do-nothing state analysis:
  - Aspirin discontinued: 0 pts (still active)
  - Ibuprofen discontinued: 0 pts (still active)
  - Warfarin still active: 30 pts (seeded as active, not touched)
  - INR lab: 0 pts
  - Encounter: 0 pts
  Do-nothing score = 30 pts -> passed=False (threshold 75) ✓

Gaming attempt (mass-discontinue all, order INR, create encounter):
  - Aspirin disc: 25 pts
  - Ibuprofen disc: 25 pts
  - Warfarin wrongly disc: 0 pts
  - INR: 10 pts
  - Encounter: 10 pts
  Gaming score = 70 pts -> passed=False (threshold 75) ✓
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 75
PID = 13


def verify_medication_safety_review(traj, env_info, task_info):
    """
    Verify that the agent correctly performed the medication safety review.

    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env
        task_info: Task info

    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available in env_info"
        }

    # Retrieve result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env('/tmp/medication_safety_review_result.json', temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run"
        }
    except (json.JSONDecodeError, Exception) as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result JSON: {e}"
        }
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    logger.info(f"Result data: {result}")

    # --- Criterion 1: Aspirin discontinued (25 pts) ---
    # The agent should have identified Aspirin as contraindicated with Warfarin and discontinued it
    aspirin_disc = int(result.get('aspirin_discontinued', 0))
    if aspirin_disc > 0:
        score += 25
        feedback_parts.append("PASS: Aspirin correctly identified and discontinued (+25 pts)")
    else:
        feedback_parts.append("FAIL: Aspirin not discontinued — antiplatelet remains on anticoagulation patient (0/25 pts)")

    # --- Criterion 2: Ibuprofen discontinued (25 pts) ---
    # The agent should have identified Ibuprofen as contraindicated with Warfarin and discontinued it
    ibuprofen_disc = int(result.get('ibuprofen_discontinued', 0))
    if ibuprofen_disc > 0:
        score += 25
        feedback_parts.append("PASS: Ibuprofen correctly identified and discontinued (+25 pts)")
    else:
        feedback_parts.append("FAIL: Ibuprofen not discontinued — NSAID remains on anticoagulation patient (0/25 pts)")

    # --- Criterion 3: Warfarin still active (30 pts) ---
    # The agent must NOT have discontinued Warfarin — it is the medically necessary anticoagulant.
    # Worth 30 pts as an anti-gaming criterion: if Warfarin is wrongly discontinued,
    # max achievable score = 25+25+10+10 = 70, which is below the pass threshold of 75.
    warfarin_active = int(result.get('warfarin_still_active', 0))
    if warfarin_active > 0:
        score += 30
        feedback_parts.append("PASS: Warfarin correctly retained as active anticoagulation therapy (+30 pts)")
    else:
        feedback_parts.append("FAIL: Warfarin was incorrectly discontinued — critical error, should never be stopped (0/30 pts)")

    # --- Criterion 4: INR lab ordered (10 pts) ---
    inr_count = int(result.get('inr_lab_count', 0))
    if inr_count > 0:
        score += 10
        feedback_parts.append("PASS: INR (anticoagulation monitoring) lab ordered (+10 pts)")
    else:
        feedback_parts.append("FAIL: INR lab not ordered (0/10 pts)")

    # --- Criterion 5: Encounter created (10 pts) ---
    enc_count = int(result.get('enc_count', 0))
    if enc_count > 0:
        score += 10
        feedback_parts.append("PASS: Encounter created to document medication safety review (+10 pts)")
    else:
        feedback_parts.append("FAIL: No encounter created (0/10 pts)")

    passed = score >= PASS_THRESHOLD
    feedback = "; ".join(feedback_parts)

    logger.info(f"Final score: {score}/100, passed: {passed}")
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
