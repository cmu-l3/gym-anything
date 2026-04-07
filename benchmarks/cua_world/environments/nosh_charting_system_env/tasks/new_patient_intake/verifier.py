#!/usr/bin/env python3
"""
Verifier for new_patient_intake task.

Patient: Hobert Wuckert (pid=11, DOB: 2000-10-27) - new patient
Scenario: Complete new patient intake workflow requiring:
  1. Social history entered (any other_history entry) (20 pts)
  2. Family history entered (2+ other_history entries) (20 pts)
  3. Insurance information added (30 pts)
  4. Initial encounter created (30 pts)

Total: 100 pts
Pass threshold: 70 pts

Do-nothing state: 0 pts (clean start, no records) -> passed=False ✓
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70
PID = 11


def verify_new_patient_intake(traj, env_info, task_info):
    """
    Verify that the agent completed the new patient intake workflow.

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
        copy_from_env('/tmp/new_patient_intake_result.json', temp_path)
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

    history_count = int(result.get('history_count', 0))
    insurance_count = int(result.get('insurance_count', 0))
    enc_count = int(result.get('enc_count', 0))

    # --- Criterion 1: Social history entered (20 pts) ---
    # other_history table should have at least 1 entry for pid=11 after setup cleanup
    if history_count >= 1:
        score += 20
        feedback_parts.append("PASS: Social history documented (+20 pts)")
    else:
        feedback_parts.append("FAIL: No social history entered (0/20 pts)")

    # --- Criterion 2: Family history entered (20 pts) ---
    # Family history adds additional entries; 2+ entries indicates both social AND family history
    # Note: NOSH may store social history as a single row and family history as additional rows
    if history_count >= 2:
        score += 20
        feedback_parts.append("PASS: Family history documented (+20 pts)")
    else:
        if history_count == 1:
            feedback_parts.append("FAIL: Only one history entry found — family history may be missing (0/20 pts)")
        else:
            feedback_parts.append("FAIL: Family history not entered (0/20 pts)")

    # --- Criterion 3: Insurance added (30 pts) ---
    if insurance_count >= 1:
        score += 30
        feedback_parts.append("PASS: Insurance information added (+30 pts)")
    else:
        feedback_parts.append("FAIL: No insurance record found (0/30 pts)")

    # --- Criterion 4: Encounter created (30 pts) ---
    if enc_count >= 1:
        score += 30
        feedback_parts.append("PASS: Initial consultation encounter created (+30 pts)")
    else:
        feedback_parts.append("FAIL: No encounter created (0/30 pts)")

    passed = score >= PASS_THRESHOLD
    feedback = "; ".join(feedback_parts)

    logger.info(f"Final score: {score}/100, passed: {passed}")
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
