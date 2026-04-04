#!/usr/bin/env python3
"""
Verifier for abnormal_hba1c_management task.

Scoring breakdown (100 points total):
  - 25 pts: HbA1c lab test completed/validated (state transition from 'requested' to done)
            Bonus: result value in 9.0-9.8% range
  - 25 pts: New E10.x condition record for Ana Betz (poor glycemic control)
  - 25 pts: New insulin prescription for Ana Betz
  - 25 pts: Urgent follow-up appointment within 7-28 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_abnormal_hba1c_management(traj, env_info, task_info):
    """Verify clinical response to critically elevated HbA1c for Ana Isabel Betz."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/abnormal_hba1c_management_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}",
            "subscores": {}
        }

    # --- CRITICAL CHECK: Correct patient ---
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Ana Isabel Betz not found in VM — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'betz' not in target_name.lower() and 'ana' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient. Expected Ana Isabel Betz, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Lab test completed with result (25 pts) ---
    lab_completed = result.get('lab_completed', False)
    lab_result_entered = result.get('lab_result_entered', False)
    lab_result_in_range = result.get('lab_result_in_valid_range', False)
    any_completed = result.get('any_completed_hbac_count', 0)
    lab_result_value = result.get('lab_result_value', 'N/A')
    lab_state = result.get('lab_state', 'unknown')

    if lab_completed and lab_result_entered and lab_result_in_range:
        score += 25
        subscores['lab_completion'] = 25
        feedback_parts.append(f"HbA1c lab completed with result {lab_result_value}% (valid range)")
    elif lab_completed or (any_completed and int(any_completed) > 0):
        score += 15
        subscores['lab_completion'] = 15
        if lab_result_entered:
            feedback_parts.append(f"HbA1c lab completed, result={lab_result_value}% (outside expected 9.0-9.8% range or value not parsed)")
        else:
            feedback_parts.append(f"HbA1c lab state updated to completed (result value not captured — check if result was entered)")
    elif lab_result_entered:
        score += 10
        subscores['lab_completion'] = 10
        feedback_parts.append(f"HbA1c result entered ({lab_result_value}%) but lab not fully validated (state: {lab_state})")
    else:
        subscores['lab_completion'] = 0
        feedback_parts.append(f"MISSING: HbA1c lab not completed (state: {lab_state}) and no result entered")

    # --- Criterion 2: E10.x condition record (25 pts) ---
    e10_found = result.get('e10_condition_found', False)
    e10_code = result.get('e10_code', 'none')

    if e10_found:
        score += 25
        subscores['e10_condition'] = 25
        feedback_parts.append(f"Diabetes condition documented ({e10_code}) — reflects poor glycemic control")
    else:
        subscores['e10_condition'] = 0
        feedback_parts.append("MISSING: No new E10.x condition record for Ana Betz (should document uncontrolled diabetes)")

    # --- Criterion 3: Insulin prescription (25 pts) ---
    prescription_found = result.get('prescription_found', False)
    insulin_confirmed = result.get('insulin_confirmed', False)

    if prescription_found and insulin_confirmed:
        score += 25
        subscores['insulin_prescription'] = 25
        feedback_parts.append("Insulin prescription created for Ana Betz")
    elif prescription_found:
        score += 15
        subscores['insulin_prescription'] = 15
        feedback_parts.append("A prescription was created but insulin not confirmed (check prescription content — should be insulin product)")
    else:
        subscores['insulin_prescription'] = 0
        feedback_parts.append("MISSING: No new prescription for Ana Betz (should prescribe insulin to intensify therapy)")

    # --- Criterion 4: Urgent follow-up (7-28 days) ---
    appt_in_range = result.get('urgent_appt_in_range', False)
    appt_date = result.get('urgent_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    win_min = result.get('urgent_window_min', '')
    win_max = result.get('urgent_window_max', '')

    if appt_in_range:
        score += 25
        subscores['urgent_followup'] = 25
        feedback_parts.append(f"Urgent follow-up scheduled {appt_date} (within 7-28 day window)")
    elif any_new_appts and int(any_new_appts) > 0:
        score += 10
        subscores['urgent_followup'] = 10
        feedback_parts.append(f"An appointment was scheduled but outside the 7-28 day urgent window ({win_min} to {win_max})")
    else:
        subscores['urgent_followup'] = 0
        feedback_parts.append(f"MISSING: No urgent follow-up appointment (7-28 days: {win_min} to {win_max})")

    # --- Final result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "target_patient": target_name
    }
