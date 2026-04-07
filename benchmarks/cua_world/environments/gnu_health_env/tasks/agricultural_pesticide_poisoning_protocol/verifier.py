#!/usr/bin/env python3
"""
Verifier for agricultural_pesticide_poisoning_protocol task.

Scoring breakdown (100 points total):
  - 20 pts: Custom Lab Creation (Cholinesterase) & Ordering it for Roberto
  - 20 pts: Custom Medicament Creation (Atropine) & Prescribing it to Roberto
  - 20 pts: T60.x Toxic effect of pesticides diagnosis for Roberto
  - 20 pts: Clinical evaluation documenting severe bradycardia (HR <= 55)
  - 20 pts: Toxicology follow-up appointment within 7-14 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_agricultural_pesticide_poisoning_protocol(traj, env_info, task_info):
    """Verify agricultural pesticide poisoning protocol for patient Roberto Carlos."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Framework error: copy_from_env missing.",
            "subscores": {}
        }

    # Retrieve exported JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/agricultural_pesticide_poisoning_protocol_result.json', local_path)
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

    # CRITICAL: Target Patient verification
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patient (Roberto Carlos) not found in system or script error.",
            "subscores": {}
        }

    # --- Criterion 1: Custom Lab Creation & Ordering (20 pts) ---
    lab_created = result.get('lab_type_created', False)
    lab_name = result.get('lab_type_name', '')
    lab_ordered = result.get('lab_ordered_for_patient', False)

    if lab_created and lab_ordered:
        score += 20
        subscores['lab_configuration'] = 20
        feedback_parts.append(f"Cholinesterase lab configured and ordered successfully ({lab_name})")
    elif lab_created:
        score += 10
        subscores['lab_configuration'] = 10
        feedback_parts.append(f"Cholinesterase lab created ({lab_name}) but NOT ordered for the patient")
    elif lab_ordered: # Edge case if name match failed but order succeeded
        score += 10
        subscores['lab_configuration'] = 10
        feedback_parts.append("Lab ordered but custom type creation validation issue.")
    else:
        subscores['lab_configuration'] = 0
        feedback_parts.append("MISSING: Cholinesterase lab type was not created and ordered")

    # --- Criterion 2: Custom Medicament & Prescription (20 pts) ---
    med_created = result.get('medicament_created', False)
    med_name = result.get('medicament_name', '')
    med_prescribed = result.get('medicament_prescribed', False)

    if med_created and med_prescribed:
        score += 20
        subscores['drug_configuration'] = 20
        feedback_parts.append(f"Atropine medicament configured and prescribed successfully ({med_name})")
    elif med_created:
        score += 10
        subscores['drug_configuration'] = 10
        feedback_parts.append(f"Atropine medicament created ({med_name}) but NOT prescribed to patient")
    else:
        subscores['drug_configuration'] = 0
        feedback_parts.append("MISSING: Atropine medicament was not created and prescribed")

    # --- Criterion 3: T60 Diagnosis (20 pts) ---
    t60_found = result.get('t60_diagnosis_found', False)
    t60_code = result.get('t60_diagnosis_code', 'none')
    t60_active = result.get('t60_diagnosis_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    
    try:
        any_new_disease = int(any_new_disease)
    except:
        any_new_disease = 0

    if t60_found and t60_active:
        score += 20
        subscores['t60_diagnosis'] = 20
        feedback_parts.append(f"T60 toxic exposure diagnosis correctly logged: {t60_code} (active)")
    elif t60_found:
        score += 15
        subscores['t60_diagnosis'] = 15
        feedback_parts.append(f"T60 diagnosis found but not marked as active: {t60_code}")
    elif any_new_disease > 0:
        score += 5
        subscores['t60_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but it was not a T60 pesticide toxic effect code")
    else:
        subscores['t60_diagnosis'] = 0
        feedback_parts.append("MISSING: No T60.x toxic exposure diagnosis documented")

    # --- Criterion 4: Clinical Evaluation for Bradycardia (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_bradycardia = result.get('evaluation_bradycardia', False)
    eval_hr = result.get('evaluation_heart_rate', 'N/A')

    if eval_found and eval_bradycardia:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Evaluation correctly documents bradycardia (HR: {eval_hr})")
    elif eval_found:
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append(f"Evaluation logged, but heart rate ({eval_hr}) does not reflect severe bradycardia (<= 55)")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 5: Follow-up Appointment 7-14 days (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days_str = result.get('appointment_days_out', 'null')
    
    try:
        appt_days = int(appt_days_str) if appt_days_str != 'null' else -999
    except ValueError:
        appt_days = -999

    if appt_found and 7 <= appt_days <= 14:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Toxicology follow-up scheduled correctly ({appt_days} days out)")
    elif appt_found:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up scheduled, but timeframe ({appt_days} days) is outside the 7-14 day window")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # Evaluate final pass/fail
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }