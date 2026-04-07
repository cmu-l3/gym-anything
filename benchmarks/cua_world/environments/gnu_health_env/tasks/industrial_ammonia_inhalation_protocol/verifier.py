#!/usr/bin/env python3
"""
Verifier for industrial_ammonia_inhalation_protocol task.

Scoring breakdown (100 points total):
  - 20 pts: Toxic inhalation diagnosis (J68.x or T59.x) for John Zenon
  - 20 pts: Clinical evaluation with RR >= 24 AND O2 Sat <= 94%
  - 20 pts: Rescue medication prescribed (Bronchodilator/Corticosteroid)
  - 20 pts: At least 2 diagnostic laboratory orders
  - 20 pts: Follow-up appointment scheduled within 7-14 days

Pass threshold: score >= 80 (Requires passing at least 4 out of 5 criteria)
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_industrial_ammonia_inhalation_protocol(traj, env_info, task_info):
    """Verify workplace chemical inhalation protocol for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/industrial_ammonia_inhalation_protocol_result.json', local_path)
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
    if 'john' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Toxic Inhalation Diagnosis J68.x/T59.x (20 pts) ---
    toxic_found = result.get('toxic_diagnosis_found', False)
    toxic_active = result.get('toxic_diagnosis_active', False)
    toxic_code = result.get('toxic_diagnosis_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if toxic_found and toxic_active:
        score += 20
        subscores['inhalation_diagnosis'] = 20
        feedback_parts.append(f"Toxic inhalation diagnosis documented: ICD-10 {toxic_code} (active)")
    elif toxic_found:
        score += 15
        subscores['inhalation_diagnosis'] = 15
        feedback_parts.append(f"Inhalation diagnosis found but NOT marked active — partial credit (code: {toxic_code})")
    elif any_new_disease > 0:
        score += 5
        subscores['inhalation_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a toxic/chemical respiratory code (expected J68.x or T59.x)")
    else:
        subscores['inhalation_diagnosis'] = 0
        feedback_parts.append("MISSING: No toxic inhalation diagnosis (J68.x/T59.x) found for John Zenon")

    # --- Criterion 2: Clinical evaluation with tachypnea + hypoxia (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_has_tachypnea = result.get('evaluation_has_tachypnea', False)
    eval_has_hypoxia = result.get('evaluation_has_hypoxia', False)
    eval_rr = result.get('evaluation_respiratory_rate', 'N/A')
    eval_o2 = result.get('evaluation_o2_sat', 'N/A')

    if eval_found and eval_has_tachypnea and eval_has_hypoxia:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented: RR={eval_rr} (tachypnea), O2 Sat={eval_o2}% (hypoxia)")
    elif eval_found and (eval_has_tachypnea or eval_has_hypoxia):
        score += 12
        subscores['clinical_evaluation'] = 12
        feedback_parts.append(f"Evaluation with partial required vitals: RR={eval_rr} tachypnea={eval_has_tachypnea}, O2={eval_o2}% hypoxia={eval_has_hypoxia}")
    elif eval_found:
        score += 6
        subscores['clinical_evaluation'] = 6
        feedback_parts.append("Evaluation created but vital signs not documented correctly (need RR>=24, O2<=94%)")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for John Zenon")

    # --- Criterion 3: Rescue Medication Prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    rescue_found = result.get('rescue_medication_found', False)
    rescue_name = result.get('rescue_medication_name', 'none')

    if prescription_found and rescue_found:
        score += 20
        subscores['rescue_prescription'] = 20
        feedback_parts.append(f"Rescue medication prescribed: {rescue_name}")
    elif prescription_found:
        score += 8
        subscores['rescue_prescription'] = 8
        feedback_parts.append("Prescription created but no bronchodilator/corticosteroid identified")
    else:
        subscores['rescue_prescription'] = 0
        feedback_parts.append("MISSING: No rescue medication prescribed")

    # --- Criterion 4: Baseline labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['baseline_labs'] = 20
        feedback_parts.append(f"Baseline lab panel ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['baseline_labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — need at least 2 for baseline toxicity assessment")
    else:
        subscores['baseline_labs'] = 0
        feedback_parts.append("MISSING: No diagnostic baseline labs ordered")

    # --- Criterion 5: Pulmonary follow-up within 7-14 days (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_in_range = result.get('appointment_in_range', False)
    appt_days_out = result.get('appointment_days_out', -1)
    
    try:
        appt_days_out = int(appt_days_out)
    except (ValueError, TypeError):
        appt_days_out = -1

    if appt_found and appt_in_range:
        score += 20
        subscores['follow_up'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled in {appt_days_out} days (within 7-14 day window)")
    elif appt_found:
        score += 10
        subscores['follow_up'] = 10
        feedback_parts.append(f"Appointment scheduled but timing is incorrect ({appt_days_out} days out, expected 7-14)")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Determine Pass/Fail ---
    # Need 80 out of 100 to pass
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "subscores": subscores
    }