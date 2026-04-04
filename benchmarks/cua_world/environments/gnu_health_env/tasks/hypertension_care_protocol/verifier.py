#!/usr/bin/env python3
"""
Verifier for hypertension_care_protocol task.

Scoring breakdown (100 points total):
  - 25 pts: Active I10 (Essential Hypertension) condition record for Roberto Carlos (new)
  - 25 pts: Prescription created for Roberto Carlos (new); bonus if Amlodipine confirmed
  - 25 pts: Lab test order created for Roberto Carlos (new); bonus if Lipid Panel
  - 25 pts: Follow-up appointment within 18-42 days of task start date

Pass threshold: score >= 70

Wrong target check: If target_patient_id is 0 (not set), score = 0.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_hypertension_care_protocol(traj, env_info, task_info):
    """Verify the complete hypertension care protocol was set up for Roberto Carlos."""
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
        copy_from_env('/tmp/hypertension_care_protocol_result.json', local_path)
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

    # --- CRITICAL CHECK: Wrong target = score 0 ---
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patient Roberto Carlos not found in VM — no patient ID recorded. Setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', 'Unknown')
    if 'roberto' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Roberto Carlos, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: I10 disease record (25 pts) ---
    i10_found = result.get('i10_disease_found', False)
    i10_active = result.get('i10_disease_active', False)

    if i10_found and i10_active:
        score += 25
        subscores['i10_disease'] = 25
        feedback_parts.append("I10 Essential Hypertension condition added (active)")
    elif i10_found and not i10_active:
        score += 10
        subscores['i10_disease'] = 10
        feedback_parts.append("I10 disease found but NOT marked active — partial credit")
    else:
        subscores['i10_disease'] = 0
        feedback_parts.append("MISSING: No Essential Hypertension (I10) condition record found for Roberto Carlos")

    # --- Criterion 2: Prescription created (25 pts) ---
    prescription_found = result.get('prescription_found', False)
    amlodipine_found = result.get('amlodipine_found', False)

    if prescription_found and amlodipine_found:
        score += 25
        subscores['prescription'] = 25
        feedback_parts.append("Amlodipine prescription created for Roberto Carlos")
    elif prescription_found:
        score += 18
        subscores['prescription'] = 18
        feedback_parts.append("A prescription was created for Roberto Carlos (drug name not confirmed as Amlodipine — check prescription content)")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No new prescription found for Roberto Carlos")

    # --- Criterion 3: Lab test order (25 pts) ---
    lab_found = result.get('lab_order_found', False)
    lipid_found = result.get('lipid_lab_found', False)
    lab_type = result.get('lab_order_type', 'unknown')

    if lab_found and lipid_found:
        score += 25
        subscores['lab_order'] = 25
        feedback_parts.append(f"Lipid Panel lab order created for Roberto Carlos")
    elif lab_found:
        score += 18
        subscores['lab_order'] = 18
        feedback_parts.append(f"A lab order was created for Roberto Carlos (type: {lab_type}) — expected Lipid Panel but any lab earns partial credit")
    else:
        subscores['lab_order'] = 0
        feedback_parts.append("MISSING: No new lab test order found for Roberto Carlos")

    # --- Criterion 4: Follow-up appointment in correct date range (25 pts) ---
    appt_in_range = result.get('followup_appt_in_range', False)
    appt_date = result.get('followup_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    win_min = result.get('followup_window_min', '')
    win_max = result.get('followup_window_max', '')

    if appt_in_range:
        score += 25
        subscores['followup_appointment'] = 25
        feedback_parts.append(f"Follow-up appointment scheduled for {appt_date} (within 18-42 day window)")
    elif any_new_appts > 0:
        score += 10
        subscores['followup_appointment'] = 10
        feedback_parts.append(f"An appointment was scheduled but NOT in the required 18-42 day window ({win_min} to {win_max})")
    else:
        subscores['followup_appointment'] = 0
        feedback_parts.append(f"MISSING: No follow-up appointment found for Roberto Carlos within 18-42 day window")

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
