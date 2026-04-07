#!/usr/bin/env python3
"""
Verifier for multi_specialist_referral_workflow task.

Patient: Malka Hartmann (pid=12, DOB: 1994-11-26)
Scenario: Multi-specialty coordination visit requiring:
  1. New encounter created (15 pts)
  2. TSH lab ordered (20 pts)
  3. CBC lab ordered (15 pts)
  4. Endocrinology referral placed (20 pts)
  5. Cardiology referral placed (20 pts)
  6. Internal message sent to Dr. Emily Brooks (10 pts)

Total: 100 pts
Pass threshold: 70 pts

Do-nothing state: 0 pts (all counts are 0) -> passed=False ✓
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70
PID = 12


def verify_multi_specialist_referral_workflow(traj, env_info, task_info):
    """
    Verify that the agent completed the multi-specialist referral workflow.

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
        copy_from_env('/tmp/multi_specialist_referral_workflow_result.json', temp_path)
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

    # --- Criterion 1: Encounter created (15 pts) ---
    enc_count = int(result.get('enc_count', 0))
    if enc_count > 0:
        score += 15
        feedback_parts.append("PASS: Encounter created for Malka Hartmann (+15 pts)")
    else:
        feedback_parts.append("FAIL: No encounter created (0/15 pts)")

    # --- Criterion 2: TSH lab ordered (20 pts) ---
    tsh_count = int(result.get('tsh_count', 0))
    if tsh_count > 0:
        score += 20
        feedback_parts.append("PASS: TSH (Thyroid Stimulating Hormone) lab ordered (+20 pts)")
    else:
        feedback_parts.append("FAIL: TSH lab not ordered (0/20 pts)")

    # --- Criterion 3: CBC lab ordered (15 pts) ---
    cbc_count = int(result.get('cbc_count', 0))
    if cbc_count > 0:
        score += 15
        feedback_parts.append("PASS: CBC (Complete Blood Count) lab ordered (+15 pts)")
    else:
        feedback_parts.append("FAIL: CBC lab not ordered (0/15 pts)")

    # --- Criterion 4: Endocrinology referral placed (20 pts) ---
    endo_count = int(result.get('endo_referral_count', 0))
    if endo_count > 0:
        score += 20
        feedback_parts.append("PASS: Endocrinology referral placed (+20 pts)")
    else:
        feedback_parts.append("FAIL: Endocrinology referral not placed (0/20 pts)")

    # --- Criterion 5: Cardiology referral placed (20 pts) ---
    cardio_count = int(result.get('cardio_referral_count', 0))
    if cardio_count > 0:
        score += 20
        feedback_parts.append("PASS: Cardiology referral placed (+20 pts)")
    else:
        feedback_parts.append("FAIL: Cardiology referral not placed (0/20 pts)")

    # --- Criterion 6: Message sent to Dr. Emily Brooks (10 pts) ---
    msg_count = int(result.get('message_count', 0))
    if msg_count > 0:
        score += 10
        feedback_parts.append("PASS: Internal message sent to Dr. Emily Brooks (+10 pts)")
    else:
        feedback_parts.append("FAIL: No internal message sent to Dr. Brooks (0/10 pts)")

    passed = score >= PASS_THRESHOLD
    feedback = "; ".join(feedback_parts)

    logger.info(f"Final score: {score}/100, passed: {passed}")
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
