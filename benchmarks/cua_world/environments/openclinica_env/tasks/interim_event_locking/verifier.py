#!/usr/bin/env python3
"""Verifier for interim_event_locking task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# OpenClinica subject_event_status_id for Locked is 7.
LOCKED_STATUS_ID = 7

def verify_interim_event_locking(traj, env_info, task_info):
    """
    Verify interim_event_locking task completion.
    
    Scoring:
    - DM-101 Baseline Locked (status 7): 30 pts
    - DM-102 Baseline Locked (status 7): 30 pts
    - DM-103 Baseline Locked (status 7): 30 pts
    - Specificity check (Week 4 NOT locked): 10 pts
    - Penalty: -30 pts if the ENTIRE study was locked/frozen instead of just the events.
    - Penalty: -20 pts if audit log proves no GUI interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/interim_event_locking_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Integrity Nonce Verification
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch."}

    score = 0
    feedback_parts = []

    # 1. Baseline Assessments Locked
    targets_locked = 0
    for subj in ["dm101", "dm102", "dm103"]:
        status = result.get(f"{subj}_baseline_status", 0)
        if status == LOCKED_STATUS_ID:
            score += 30
            targets_locked += 1
            feedback_parts.append(f"✓ {subj.upper()} Baseline Assessment successfully locked (+30)")
        else:
            feedback_parts.append(f"✗ {subj.upper()} Baseline Assessment NOT locked (status={status})")

    # 2. Specificity Check: Week 4 NOT Locked
    specificity_passed = True
    for subj in ["dm101", "dm102", "dm103"]:
        status = result.get(f"{subj}_week4_status", 0)
        if status == LOCKED_STATUS_ID:
            specificity_passed = False
            feedback_parts.append(f"✗ COLLATERAL DAMAGE: {subj.upper()} Week 4 Follow-up was incorrectly locked!")
    
    if specificity_passed:
        score += 10
        feedback_parts.append("✓ Specificity check passed: Week 4 Follow-up events left unlocked (+10)")
    else:
        feedback_parts.append("✗ Specificity check failed: Collateral events were locked (0/10)")

    # 3. Penalty Check: Study Locked Instead of Event
    study_status = result.get("study_status_id", 1)
    # status 5=Frozen, 6=Locked, 4=Completed
    if study_status in [5, 6]:
        score -= 30
        feedback_parts.append(f"⚠ PENALTY: You locked/froze the entire study (status={study_status}) instead of targeting the specific events! (-30)")

    # 4. Penalty Check: Audit Log bypass
    audit_log = result.get('audit_log_count', 0)
    audit_base = result.get('audit_baseline_count', 0)
    if audit_log <= audit_base:
        score -= 20
        feedback_parts.append("⚠ PENALTY: No GUI audit logs detected. Database bypassed directly? (-20)")

    score = max(0, min(100, score))
    passed = (score >= 70) and specificity_passed and (study_status not in [5, 6])

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }