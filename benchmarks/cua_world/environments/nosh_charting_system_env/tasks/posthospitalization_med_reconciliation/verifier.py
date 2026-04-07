#!/usr/bin/env python3
"""
Verifier for posthospitalization_med_reconciliation task.

Patient: Sherill Botsford (pid=10, DOB: 1995-01-24)
Scenario: Post-hospitalization medication reconciliation. Setup seeds:
  - Lisinopril 5mg (active, pre-admission dose)
  - Amlodipine 5mg (active, pre-admission dose)
Agent must:
  1. Discontinue Lisinopril 5mg (25 pts)
  2. Discontinue Amlodipine 5mg (25 pts)
  3. Add Lisinopril 10mg as active medication (20 pts)
  4. Add Amlodipine 10mg as active medication (20 pts)
  5. Create encounter (10 pts)

Total: 100 pts
Pass threshold: 70 pts

Do-nothing state: 0 pts (seeded meds active, no new meds, no encounter) -> passed=False ✓
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70
PID = 10


def verify_posthospitalization_med_reconciliation(traj, env_info, task_info):
    """
    Verify that the agent correctly performed post-hospitalization medication reconciliation.

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
        copy_from_env('/tmp/posthospitalization_med_reconciliation_result.json', temp_path)
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

    # --- Criterion 1: Lisinopril 5mg discontinued (25 pts) ---
    lis5_disc = int(result.get('lisinopril_5mg_discontinued', 0))
    if lis5_disc > 0:
        score += 25
        feedback_parts.append("PASS: Lisinopril 5mg discontinued (+25 pts)")
    else:
        feedback_parts.append("FAIL: Lisinopril 5mg not discontinued (0/25 pts)")

    # --- Criterion 2: Amlodipine 5mg discontinued (25 pts) ---
    aml5_disc = int(result.get('amlodipine_5mg_discontinued', 0))
    if aml5_disc > 0:
        score += 25
        feedback_parts.append("PASS: Amlodipine 5mg discontinued (+25 pts)")
    else:
        feedback_parts.append("FAIL: Amlodipine 5mg not discontinued (0/25 pts)")

    # --- Criterion 3: Lisinopril 10mg added as active medication (20 pts) ---
    lis10_active = int(result.get('lisinopril_10mg_active', 0))
    if lis10_active > 0:
        score += 20
        feedback_parts.append("PASS: Lisinopril 10mg added as active medication (+20 pts)")
    else:
        feedback_parts.append("FAIL: Lisinopril 10mg not added as active medication (0/20 pts)")

    # --- Criterion 4: Amlodipine 10mg added as active medication (20 pts) ---
    aml10_active = int(result.get('amlodipine_10mg_active', 0))
    if aml10_active > 0:
        score += 20
        feedback_parts.append("PASS: Amlodipine 10mg added as active medication (+20 pts)")
    else:
        feedback_parts.append("FAIL: Amlodipine 10mg not added as active medication (0/20 pts)")

    # --- Criterion 5: Encounter created (10 pts) ---
    enc_count = int(result.get('enc_count', 0))
    init_enc = int(result.get('init_enc_baseline', 0))
    new_enc = enc_count - init_enc
    if new_enc > 0:
        score += 10
        feedback_parts.append("PASS: Encounter created for medication reconciliation visit (+10 pts)")
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
