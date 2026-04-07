#!/usr/bin/env python3
"""
Verifier for occupational_contact_dermatitis task.

Scoring breakdown (100 points total):
  - 20 pts: Diagnosis of Contact Dermatitis (L23.x or L24.x)
  - 20 pts: Allergy/Adverse Reaction recorded
  - 20 pts: Clinical Evaluation created
  - 20 pts: Prescribed Corticosteroid or Antihistamine
  - 20 pts: Appointment scheduled 7-14 days from today

Pass threshold: score >= 70 AND (Diagnosis + Prescription must be met)
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_occupational_contact_dermatitis(traj, env_info, task_info):
    """Verify occupational contact dermatitis incident documentation."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_contact_dermatitis_result.json', local_path)
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

    # CRITICAL CHECK: Correct patient
    target_id = result.get('target_patient_id', 0)
    target_name = result.get('target_patient_name', '')
    
    if not target_id or 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong or missing patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # Criterion 1: Diagnosis (20 pts)
    diag_found = result.get('diagnosis_found', False)
    diag_active = result.get('diagnosis_active', False)
    diag_code = result.get('diagnosis_code', 'none')
    any_new_disease = int(result.get('any_new_disease_count', 0))

    crit1_pass = False
    if diag_found and diag_active:
        score += 20
        subscores['diagnosis'] = 20
        crit1_pass = True
        feedback_parts.append(f"Contact dermatitis diagnosis documented: ICD-10 {diag_code} (active)")
    elif diag_found:
        score += 15
        subscores['diagnosis'] = 15
        crit1_pass = True
        feedback_parts.append(f"Diagnosis {diag_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an L23/L24 code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No L23 or L24 diagnosis found for John Zenon")

    # Criterion 2: Allergy / Sensitization (20 pts)
    allergy_found = result.get('allergy_found', False)
    allergen_name = result.get('allergen_name', 'none')

    if allergy_found:
        score += 20
        subscores['allergy'] = 20
        feedback_parts.append(f"Allergy/Sensitization recorded: {allergen_name}")
    else:
        subscores['allergy'] = 0
        feedback_parts.append("MISSING: No allergy/adverse reaction recorded")

    # Criterion 3: Clinical Evaluation (20 pts)
    eval_found = result.get('evaluation_found', False)

    if eval_found:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append("Clinical evaluation documented")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 4: Prescription (20 pts)
    presc_found = result.get('prescription_found', False)
    drug_match = result.get('drug_match_found', False)
    prescribed_drug = result.get('prescribed_drug', 'none')

    crit4_pass = False
    if presc_found and drug_match:
        score += 20
        subscores['prescription'] = 20
        crit4_pass = True
        feedback_parts.append(f"Appropriate medication prescribed: {prescribed_drug}")
    elif presc_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but did not contain a target corticosteroid or antihistamine")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No prescription orders found")

    # Criterion 5: Follow-up Appointment (20 pts)
    appt_found = result.get('appointment_found', False)
    appt_dates = result.get('appointment_dates', [])
    task_start_str = result.get('task_start_date', '')
    
    appt_score = 0
    if appt_found and appt_dates and task_start_str:
        try:
            start_date = datetime.strptime(task_start_str, "%Y-%m-%d").date()
            valid_appt = False
            for d_str in appt_dates:
                # Truncate time if present
                d_str_clean = d_str.split(' ')[0]
                appt_date = datetime.strptime(d_str_clean, "%Y-%m-%d").date()
                delta_days = (appt_date - start_date).days
                if 7 <= delta_days <= 14:
                    valid_appt = True
                    break
            
            if valid_appt:
                appt_score = 20
                feedback_parts.append("Follow-up appointment scheduled within 7-14 days")
            else:
                appt_score = 10
                feedback_parts.append("Appointment scheduled, but outside the 7-14 day window")
        except Exception as e:
            appt_score = 5
            feedback_parts.append(f"Appointment created but date could not be parsed: {e}")
    elif appt_found:
        appt_score = 5
        feedback_parts.append("Appointment created but lacked readable dates")
    else:
        feedback_parts.append("MISSING: No follow-up appointment scheduled")
        
    score += appt_score
    subscores['appointment'] = appt_score

    # Final logic
    key_criteria_met = crit1_pass and crit4_pass
    passed = score >= 70 and key_criteria_met

    if not key_criteria_met and score >= 70:
        feedback_parts.append("FAILED: Met point threshold, but missing critical Diagnosis or Medication criteria")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }