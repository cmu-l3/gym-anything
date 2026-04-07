#!/usr/bin/env python3
"""
Verifier for occupational_cold_stress_protocol task.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_cold_stress_protocol(traj, env_info, task_info):
    """Verify cold stress protocol for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_cold_stress_protocol_result.json', local_path)
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

    # Verify Patient
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

    # Criterion 1: Cold stress diagnosis
    cold_found = result.get('cold_found', False)
    cold_code = result.get('cold_code', 'none')
    cold_active = result.get('cold_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)

    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if cold_found and cold_active:
        score += 20
        subscores['cold_diagnosis'] = 20
        feedback_parts.append(f"Cold stress diagnosis documented: ICD-10 {cold_code} (active)")
    elif cold_found:
        score += 15
        subscores['cold_diagnosis'] = 15
        feedback_parts.append(f"Cold stress diagnosis found ({cold_code}) but NOT marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['cold_diagnosis'] = 5
        feedback_parts.append(f"A diagnosis was added but not a cold stress code (T33/T68)")
    else:
        subscores['cold_diagnosis'] = 0
        feedback_parts.append("MISSING: No cold stress diagnosis (T33.x or T68.x) found for John Zenon")

    # Criterion 2: Clinical evaluation with hypothermia
    eval_found = result.get('evaluation_found', False)
    eval_hypothermic = result.get('evaluation_hypothermic', False)
    eval_temp = result.get('evaluation_temperature', 'N/A')

    if eval_found and eval_hypothermic:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with hypothermic temperature: {eval_temp}C")
    elif eval_found and eval_temp != 'null':
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append(f"Clinical evaluation documented but temperature ({eval_temp}C) is not hypothermic (<= 35.5)")
    elif eval_found:
        score += 5
        subscores['clinical_evaluation'] = 5
        feedback_parts.append("Clinical evaluation created but temperature not documented")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for John Zenon")

    # Criterion 3: Baseline Labs >= 2
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
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — expected at least 2 for cold stress baseline")
    else:
        subscores['baseline_labs'] = 0
        feedback_parts.append("MISSING: No baseline laboratory orders placed")

    # Criterion 4: Analgesic prescription
    prescription_found = result.get('prescription_found', False)
    analgesic_found = result.get('analgesic_found', False)
    analgesic_name = result.get('analgesic_name', 'none')

    if prescription_found and analgesic_found:
        score += 20
        subscores['analgesic_rx'] = 20
        feedback_parts.append(f"Analgesic prescribed for rewarming pain: {analgesic_name}")
    elif prescription_found:
        score += 10
        subscores['analgesic_rx'] = 10
        feedback_parts.append("Prescription created but no appropriate analgesic (Ibuprofen/Ketorolac/Acetaminophen/Aspirin) found")
    else:
        subscores['analgesic_rx'] = 0
        feedback_parts.append("MISSING: No analgesic prescription ordered")

    # Criterion 5: Follow-up Appointment (2-7 days)
    appt_found = result.get('appointment_found', False)
    appt_in_range = result.get('appointment_in_range', False)
    appt_delta = result.get('appointment_days_delta', 0)

    try:
        appt_delta = int(appt_delta)
    except (ValueError, TypeError):
        appt_delta = 0

    if appt_found and appt_in_range:
        score += 20
        subscores['follow_up'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled appropriately ({appt_delta} days out)")
    elif appt_found:
        score += 10
        subscores['follow_up'] = 10
        feedback_parts.append(f"Follow-up scheduled but timing ({appt_delta} days) is outside the 2-7 day window")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }