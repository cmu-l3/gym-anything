#!/usr/bin/env python3
"""
Verifier for industrial_electrical_shock_protocol task.

Scoring breakdown (100 points total):
  - 20 pts: Electrical shock diagnosis (T75.x or W86.x) for John Zenon
  - 20 pts: Clinical evaluation with heart rate exactly 115 bpm
  - 20 pts: At least 2 monitoring laboratory orders
  - 20 pts: Prescription for an analgesic or burn care treatment
  - 20 pts: Follow-up appointment scheduled 1 to 5 days from task start

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_industrial_electrical_shock_protocol(traj, env_info, task_info):
    """Verify industrial electrical shock protocol for patient John Zenon."""
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
        copy_from_env('/tmp/industrial_electrical_shock_protocol_result.json', local_path)
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
            "feedback": "CRITICAL: Patient John Zenon not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Shock diagnosis (20 pts) ---
    shock_found = result.get('shock_found', False)
    shock_code = result.get('shock_code', 'none')
    shock_active = result.get('shock_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if shock_found and shock_active:
        score += 20
        subscores['shock_diagnosis'] = 20
        feedback_parts.append(f"Electrical shock diagnosis documented: ICD-10 {shock_code} (active)")
    elif shock_found:
        score += 15
        subscores['shock_diagnosis'] = 15
        feedback_parts.append(f"Shock diagnosis {shock_code} found but not marked active")
    elif any_new_disease > 0:
        score += 8
        subscores['shock_diagnosis'] = 8
        feedback_parts.append("A diagnosis was added but not an electrocution-related T75/W86 code")
    else:
        subscores['shock_diagnosis'] = 0
        feedback_parts.append("MISSING: No electrical shock diagnosis documented for John Zenon")

    # --- Criterion 2: Clinical evaluation with HR=115 (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_hr = result.get('evaluation_heart_rate', 'N/A')

    if eval_found and eval_hr == '115':
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append("Clinical evaluation documented with heart rate exactly 115 bpm")
    elif eval_found and eval_hr != 'null':
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append(f"Evaluation created but HR was {eval_hr} (expected 115)")
    elif eval_found:
        score += 5
        subscores['clinical_evaluation'] = 5
        feedback_parts.append("Evaluation created but heart rate was missing")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Adequate lab workup ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['lab_orders'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}); minimum 2 required")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No lab tests ordered")

    # --- Criterion 4: Prescription for Analgesic/Burn Care (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    drug_found = result.get('drug_found', False)
    drug_name = result.get('drug_name', 'none')

    if prescription_found and drug_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Appropriate prescription documented: {drug_name}")
    elif prescription_found:
        score += 10
        subscores['prescription'] = 10
        feedback_parts.append("A prescription was created but it did not match an expected analgesic or topical burn medication")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No prescription created for the patient")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_date_str = result.get('appointment_date', 'none')
    task_start_str = result.get('task_start_date', '')

    if appt_found and appt_date_str != 'none' and task_start_str:
        try:
            appt_date = datetime.strptime(appt_date_str, '%Y-%m-%d').date()
            start_date = datetime.strptime(task_start_str, '%Y-%m-%d').date()
            days_diff = (appt_date - start_date).days

            if 1 <= days_diff <= 5:
                score += 20
                subscores['follow_up'] = 20
                feedback_parts.append(f"Follow-up scheduled correctly ({days_diff} days from today)")
            elif days_diff == 0:
                score += 10
                subscores['follow_up'] = 10
                feedback_parts.append(f"Appointment scheduled for today (expected 1-5 days out)")
            elif days_diff > 5:
                score += 10
                subscores['follow_up'] = 10
                feedback_parts.append(f"Appointment scheduled too far in the future ({days_diff} days from today; expected 1-5)")
            else:
                score += 5
                subscores['follow_up'] = 5
                feedback_parts.append(f"Appointment scheduled in the past ({days_diff} days)")
        except ValueError:
            score += 10
            subscores['follow_up'] = 10
            feedback_parts.append(f"Appointment found but date unparseable ({appt_date_str})")
    elif appt_found:
        score += 5
        subscores['follow_up'] = 5
        feedback_parts.append("Appointment record created but without a valid date")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Final Assessment ---
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }