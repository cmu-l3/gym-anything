#!/usr/bin/env python3
"""
Verifier for comprehensive_chronic_disease_visit task.

Patient: Kelle Crist (pid=9, DOB: 2002-10-18)
Scenario: Quarterly diabetes management visit requiring:
  1. New encounter created (20 pts)
  2. HbA1c lab ordered (20 pts)
  3. CMP lab ordered (15 pts)
  4. Endocrinology referral placed (25 pts)
  5. Metformin 500mg added to active medications (20 pts)

Total: 100 pts
Pass threshold: 70 pts (all four major items)

Do-nothing state: 0 pts -> passed=False ✓
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70
PID = 9


def verify_comprehensive_chronic_disease_visit(traj, env_info, task_info):
    """
    Verify that the agent completed all four components of the diabetes visit.

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
        copy_from_env('/tmp/comprehensive_chronic_disease_visit_result.json', temp_path)
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

    # --- Criterion 1: Encounter created (20 pts) ---
    enc_count = int(result.get('enc_count', 0))
    init_enc = int(result.get('init_enc_baseline', 0))
    new_enc = enc_count - init_enc
    if new_enc > 0:
        score += 20
        feedback_parts.append("PASS: Encounter created for Kelle Crist (+20 pts)")
    else:
        feedback_parts.append("FAIL: No new encounter created (0/20 pts)")

    # --- Criterion 2: HbA1c lab ordered (20 pts) ---
    a1c_count = int(result.get('a1c_count', 0))
    if a1c_count > 0:
        score += 20
        feedback_parts.append("PASS: HbA1c lab test ordered (+20 pts)")
    else:
        feedback_parts.append("FAIL: HbA1c lab not ordered (0/20 pts)")

    # --- Criterion 3: CMP lab ordered (15 pts) ---
    cmp_count = int(result.get('cmp_count', 0))
    if cmp_count > 0:
        score += 15
        feedback_parts.append("PASS: CMP (Comprehensive Metabolic Panel) lab ordered (+15 pts)")
    else:
        feedback_parts.append("FAIL: CMP lab not ordered (0/15 pts)")

    # --- Criterion 4: Endocrinology referral placed (25 pts) ---
    endo_count = int(result.get('endo_referral_count', 0))
    if endo_count > 0:
        score += 25
        feedback_parts.append("PASS: Endocrinology referral placed (+25 pts)")
    else:
        feedback_parts.append("FAIL: Endocrinology referral not placed (0/25 pts)")

    # --- Criterion 5: Metformin added as active medication (20 pts) ---
    metformin_count = int(result.get('metformin_active_count', 0))
    if metformin_count > 0:
        score += 20
        feedback_parts.append("PASS: Metformin added as active medication (+20 pts)")
    else:
        feedback_parts.append("FAIL: Metformin not added to active medication list (0/20 pts)")

    passed = score >= PASS_THRESHOLD
    feedback = "; ".join(feedback_parts)

    logger.info(f"Final score: {score}/100, passed: {passed}")
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
