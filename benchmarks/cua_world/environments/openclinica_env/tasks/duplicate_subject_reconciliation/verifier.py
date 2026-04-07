#!/usr/bin/env python3
"""Verifier for duplicate_subject_reconciliation task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def _safe_int(value, default=0):
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except (ValueError, AttributeError):
            return default
    return default

def verify_duplicate_subject_reconciliation(traj, env_info, task_info):
    """
    Verify duplicate_subject_reconciliation task completion.

    Scoring (100 points):
    - DM-106 Removed (status_id = 4 or 5): 25 pts
    - DM-105 Week 4 Follow-up Event Scheduled: 15 pts
    - DM-105 Week 4 Follow-up CRF Complete (status_id = 2): 20 pts
    - Values Transcribed (135, 85, 72, 36.5, 80.5): 8 pts each = 40 pts
    - Audit log penalty: -25 if no GUI interaction detected
    - Collateral Damage Penalty: -50 if DM-105 is removed

    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/duplicate_reconciliation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
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
        return {"passed": False, "score": 0,
                "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering"}

    score = 0
    feedback_parts = []

    dm106_status = _safe_int(result.get('dm106_status_id', 1), default=1)
    dm105_status = _safe_int(result.get('dm105_status_id', 1), default=1)
    dm105_event_exists = result.get('dm105_wk4_event_exists', False)
    dm105_crf_status = _safe_int(result.get('dm105_crf_status_id', 0), default=0)
    crf_values_raw = result.get('dm105_crf_values', '')
    crf_values_list = [v.strip() for v in crf_values_raw.split(',')] if crf_values_raw else []

    # Criterion 1: DM-106 Removed (status_id 4 or 5)
    if dm106_status in (4, 5):
        score += 25
        feedback_parts.append("DM-106 successfully removed (+25)")
    elif dm106_status == 3:
        score += 15
        feedback_parts.append("DM-106 discontinued but not fully removed (+15)")
    else:
        feedback_parts.append(f"FAIL: DM-106 status is {dm106_status}, expected 4 or 5 (Removed)")

    # Collateral check
    if dm105_status in (4, 5):
        score -= 50
        feedback_parts.append("PENALTY: Primary subject DM-105 was accidentally removed! (-50)")

    # Criterion 2: DM-105 Event Scheduled
    if dm105_event_exists:
        score += 15
        feedback_parts.append("DM-105 Week 4 Follow-up event scheduled (+15)")
    else:
        feedback_parts.append("FAIL: DM-105 Week 4 Follow-up not scheduled")

    # Criterion 3: CRF Complete
    if dm105_crf_status == 2:
        score += 20
        feedback_parts.append("DM-105 Week 4 Follow-up CRF marked complete (+20)")
    elif dm105_crf_status == 1:
        score += 10
        feedback_parts.append("DM-105 Week 4 Follow-up CRF exists but not marked complete (+10)")

    # Criterion 4: Values Transcribed
    expected_values = ['135', '85', '72', '36.5', '80.5']
    found_values_count = 0
    for val in expected_values:
        # Check exact string or common numeric representations
        if val in crf_values_list or f"{val}.0" in crf_values_list or f"{val}0" in crf_values_list:
            score += 8
            found_values_count += 1

    if found_values_count == 5:
        feedback_parts.append("All 5 vital signs successfully transcribed (+40)")
    elif found_values_count > 0:
        feedback_parts.append(f"{found_values_count}/5 vital signs transcribed (+{found_values_count*8})")
    else:
        feedback_parts.append("FAIL: No vital signs transcribed")

    # Audit log check
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    if audit_count <= audit_baseline:
        score -= 25
        feedback_parts.append("PENALTY: No GUI interaction detected in audit log (-25)")

    # Final score validation
    score = max(0, min(100, score))
    passed = score >= 75 and dm106_status in (4, 5) and dm105_event_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }