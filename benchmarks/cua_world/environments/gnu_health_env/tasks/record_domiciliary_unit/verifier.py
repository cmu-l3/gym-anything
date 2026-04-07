#!/usr/bin/env python3
"""
Verifier for record_domiciliary_unit task.

This is a hard task. The agent must independently manage an environmental 
health assessment across Domiciliary Units, patients, diseases, labs, and appointments.

Scoring breakdown (100 points total):
  - 20 pts: DU 'DU-CAPUT-001' created
  - 20 pts: Patient Bonifacio Caput linked to DU
  - 20 pts: Active COPD diagnosis (J44.x)
  - 20 pts: At least 2 baseline laboratory orders
  - 20 pts: Reassessment follow-up appointment within 30-60 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_record_domiciliary_unit(traj, env_info, task_info):
    """Verify environmental health housing assessment for Bonifacio Caput."""
    copy_from_env = env_info.get('copy_from_env')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Framework error: copy_from_env not available.",
            "subscores": {}
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_domiciliary_unit_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Bonifacio Caput not found — setup may have failed.",
            "subscores": {}
        }

    # --- Criterion 1: DU Created (20 pts) ---
    du_created = result.get('du_created', False)
    any_new_du = int(result.get('any_new_du_count', 0))
    
    if du_created:
        score += 20
        subscores['du_created'] = 20
        feedback_parts.append("Domiciliary Unit 'DU-CAPUT-001' was successfully created.")
    elif any_new_du > 0:
        score += 10
        subscores['du_created'] = 10
        feedback_parts.append(f"A new DU was created, but not with the exact name 'DU-CAPUT-001'.")
    else:
        subscores['du_created'] = 0
        feedback_parts.append("MISSING: No Domiciliary Unit was created.")

    # --- Criterion 2: Patient linked to DU (20 pts) ---
    patient_linked = result.get('patient_linked_correctly', False)
    patient_du_field = result.get('patient_du_field', 'null')
    
    if patient_linked:
        score += 20
        subscores['patient_linked'] = 20
        feedback_parts.append("Patient Bonifacio Caput was successfully linked to the correct DU.")
    elif patient_du_field != 'null' and patient_du_field != '':
        score += 10
        subscores['patient_linked'] = 10
        feedback_parts.append("Patient is linked to a DU, but not the requested 'DU-CAPUT-001'.")
    else:
        subscores['patient_linked'] = 0
        feedback_parts.append("MISSING: Patient was not linked to any Domiciliary Unit.")

    # --- Criterion 3: COPD Diagnosis J44.x (20 pts) ---
    j44_found = result.get('j44_found', False)
    j44_active = result.get('j44_active', False)
    j44_code = result.get('j44_code', 'none')
    any_j_code = result.get('any_j_code_found', False)
    any_disease = int(result.get('any_new_disease_count', 0))
    
    if j44_found and j44_active:
        score += 20
        subscores['copd_diagnosis'] = 20
        feedback_parts.append(f"Active COPD diagnosis documented: ICD-10 {j44_code}.")
    elif j44_found:
        score += 15
        subscores['copd_diagnosis'] = 15
        feedback_parts.append(f"COPD diagnosis {j44_code} found but not marked as active.")
    elif any_j_code:
        score += 10
        subscores['copd_diagnosis'] = 10
        feedback_parts.append("A respiratory (J-code) diagnosis was found, but not specifically COPD (J44.x).")
    elif any_disease > 0:
        score += 5
        subscores['copd_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but it is not a respiratory disease code.")
    else:
        subscores['copd_diagnosis'] = 0
        feedback_parts.append("MISSING: No new disease records found for Bonifacio Caput.")

    # --- Criterion 4: Baseline Labs >= 2 (20 pts) ---
    lab_count = int(result.get('new_lab_count', 0))
    lab_types = result.get('new_lab_types', '')
    
    if lab_count >= 2:
        score += 20
        subscores['baseline_labs'] = 20
        feedback_parts.append(f"Sufficient lab orders created: {lab_count} ({lab_types}).")
    elif lab_count == 1:
        score += 10
        subscores['baseline_labs'] = 10
        feedback_parts.append(f"Only 1 lab order created ({lab_types}). Task requires at least 2.")
    else:
        subscores['baseline_labs'] = 0
        feedback_parts.append("MISSING: No laboratory test orders were found for the patient.")

    # --- Criterion 5: Reassessment Follow-up 30-60 days (20 pts) ---
    appt_found = result.get('appointment_found', False)
    try:
        days_out = int(result.get('appointment_days_out', -999))
    except (ValueError, TypeError):
        days_out = -999

    if appt_found and 30 <= days_out <= 60:
        score += 20
        subscores['followup_appt'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled correctly ({days_out} days from now).")
    elif appt_found and days_out > 0:
        score += 10
        subscores['followup_appt'] = 10
        feedback_parts.append(f"Appointment scheduled, but timeframe is incorrect ({days_out} days out, expected 30-60).")
    elif int(result.get('any_new_appointment_count', 0)) > 0:
        score += 5
        subscores['followup_appt'] = 5
        feedback_parts.append("An appointment was scheduled, but not for Bonifacio Caput.")
    else:
        subscores['followup_appt'] = 0
        feedback_parts.append("MISSING: No follow-up appointment was scheduled for the patient.")

    # --- Final Assessment ---
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }