#!/usr/bin/env python3
"""
Verifier for warehouse_co_exposure_management task.

This task requires the agent to independently complete an occupational health 
clinical encounter for an acute CO exposure across multiple HIS modules.

Scoring breakdown (100 points total):
  - 20 pts: T58 CO Poisoning diagnosis (active)
  - 20 pts: Clinical evaluation with tachycardia (HR>=100) and tachypnea (RR>=20)
  - 20 pts: Prescription for an analgesic (Paracetamol / Ibuprofen)
  - 20 pts: At least 2 baseline laboratory test orders
  - 20 pts: Follow-up appointment scheduled 1 to 5 days from today

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_warehouse_co_exposure_management(traj, env_info, task_info):
    """Verify warehouse CO exposure management for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Framework error: Copy function not available."
        }
    
    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/warehouse_co_exposure_management_result.json', local_path)
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

    # --- Criterion 1: T58 Diagnosis (20 pts) ---
    t58_found = result.get('t58_found', False)
    t58_active = result.get('t58_active', False)
    t58_code = result.get('t58_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if t58_found and t58_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Diagnosis documented: ICD-10 {t58_code} (active)")
    elif t58_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"T58 diagnosis found but not marked active (code: {t58_code})")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a T58 CO Poisoning classification")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No T58.x CO poisoning diagnosis for John Zenon")

    # --- Criterion 2: Clinical Evaluation (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_tachycardia = result.get('evaluation_has_tachycardia', False)
    eval_tachypnea = result.get('evaluation_has_tachypnea', False)
    eval_hr = result.get('evaluation_heart_rate', 'N/A')
    eval_rr = result.get('evaluation_respiratory_rate', 'N/A')

    if eval_found and eval_tachycardia and eval_tachypnea:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with appropriate vitals: HR={eval_hr}, RR={eval_rr}")
    elif eval_found and (eval_tachycardia or eval_tachypnea):
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append(f"Evaluation with partial vitals: HR={eval_hr} (tachy={eval_tachycardia}), RR={eval_rr} (tachypnea={eval_tachypnea})")
    elif eval_found:
        score += 5
        subscores['clinical_evaluation'] = 5
        feedback_parts.append("Evaluation created but vital signs (HR>=100, RR>=20) not documented correctly")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Analgesic Prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    analgesic_found = result.get('analgesic_found', False)
    analgesic_name = result.get('analgesic_name', 'none')

    if prescription_found and analgesic_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Analgesic prescribed: {analgesic_name}")
    elif prescription_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but no matching analgesic (Paracetamol/Ibuprofen) found")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No analgesic prescription ordered")

    # --- Criterion 4: Baseline Labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Baseline lab panel: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['lab_orders'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — minimum 2 required")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No baseline labs ordered")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days_diff_str = result.get('appointment_days_diff', 'null')

    if appt_found and appt_days_diff_str != 'null':
        try:
            appt_days_diff = int(appt_days_diff_str)
            if 1 <= appt_days_diff <= 5:
                score += 20
                subscores['appointment'] = 20
                feedback_parts.append(f"Follow-up scheduled correctly ({appt_days_diff} days from today)")
            else:
                score += 10
                subscores['appointment'] = 10
                feedback_parts.append(f"Follow-up scheduled but timeline incorrect ({appt_days_diff} days from today; expected 1-5 days)")
        except ValueError:
            score += 5
            subscores['appointment'] = 5
            feedback_parts.append("Appointment found but date format could not be verified")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }