#!/usr/bin/env python3
"""
Verifier for new_diabetes_patient_workup task.

Scoring breakdown (100 points total):
  - 20 pts: E11 (Type 2 Diabetes Mellitus) condition record for Bonifacio Caput (new, active)
  - 20 pts: Penicillin allergy documented for Bonifacio Caput (severity=Severe preferred)
  - 20 pts: HbA1c (GLYCATED HEMOGLOBIN) lab test ordered for Bonifacio Caput
  - 20 pts: Metformin prescription created for Bonifacio Caput
  - 20 pts: Follow-up appointment with Dr. Cordara in 35-60 day window

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_new_diabetes_patient_workup(traj, env_info, task_info):
    """Verify the full new diabetes patient workup was completed for Bonifacio Caput."""
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
        copy_from_env('/tmp/new_diabetes_patient_workup_result.json', local_path)
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

    # --- CRITICAL CHECK: Verify correct patient ---
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patient Bonifacio Caput not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'bonifacio' not in target_name.lower() and 'caput' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient. Expected Bonifacio Caput, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: E11 disease record (20 pts) ---
    e11_found = result.get('e11_disease_found', False)
    e11_active = result.get('e11_disease_active', False)

    if e11_found and e11_active:
        score += 20
        subscores['e11_disease'] = 20
        feedback_parts.append("E11 Type 2 Diabetes condition added (active)")
    elif e11_found:
        score += 10
        subscores['e11_disease'] = 10
        feedback_parts.append("E11 disease found but not marked active — partial credit")
    else:
        subscores['e11_disease'] = 0
        feedback_parts.append("MISSING: No E11 (Type 2 Diabetes) condition for Bonifacio Caput")

    # --- Criterion 2: Penicillin allergy (20 pts) ---
    allergy_found = result.get('penicillin_allergy_found', False)
    allergy_total = result.get('penicillin_allergy_total', 0)
    allergy_severity = result.get('penicillin_allergy_severity', '').lower()

    # Accept either new allergy (via baseline) or any existing allergy for the patient
    allergy_present = allergy_found or (allergy_total and int(allergy_total) > 0)

    if allergy_present and ('severe' in allergy_severity or 'very' in allergy_severity):
        score += 20
        subscores['penicillin_allergy'] = 20
        feedback_parts.append(f"Penicillin allergy documented (severity={allergy_severity})")
    elif allergy_present:
        score += 14
        subscores['penicillin_allergy'] = 14
        feedback_parts.append(f"Penicillin allergy documented but severity not 'Severe' (got: {allergy_severity or 'not captured'})")
    else:
        subscores['penicillin_allergy'] = 0
        feedback_parts.append("MISSING: No Penicillin allergy documented for Bonifacio Caput")

    # --- Criterion 3: HbA1c lab order (20 pts) ---
    hba1c_found = result.get('hba1c_lab_found', False)

    if hba1c_found:
        score += 20
        subscores['hba1c_lab'] = 20
        feedback_parts.append("GLYCATED HEMOGLOBIN (HbA1c) lab test ordered")
    else:
        subscores['hba1c_lab'] = 0
        feedback_parts.append("MISSING: No HbA1c lab test order for Bonifacio Caput")

    # --- Criterion 4: Metformin prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    metformin_confirmed = result.get('metformin_confirmed', False)

    if prescription_found and metformin_confirmed:
        score += 20
        subscores['metformin_prescription'] = 20
        feedback_parts.append("Metformin prescription created")
    elif prescription_found:
        score += 14
        subscores['metformin_prescription'] = 14
        feedback_parts.append("A prescription was created (Metformin drug name not confirmed — check prescription lines)")
    else:
        subscores['metformin_prescription'] = 0
        feedback_parts.append("MISSING: No prescription found for Bonifacio Caput")

    # --- Criterion 5: Follow-up appointment (20 pts) ---
    appt_in_range = result.get('followup_appt_in_range', False)
    appt_date = result.get('followup_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    win_min = result.get('followup_window_min', '')
    win_max = result.get('followup_window_max', '')

    if appt_in_range:
        score += 20
        subscores['followup_appointment'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled for {appt_date} (35-60 day window)")
    elif any_new_appts and int(any_new_appts) > 0:
        score += 8
        subscores['followup_appointment'] = 8
        feedback_parts.append(f"An appointment was scheduled but NOT in 35-60 day window ({win_min} to {win_max})")
    else:
        subscores['followup_appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment in 35-60 day window for Bonifacio Caput")

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
