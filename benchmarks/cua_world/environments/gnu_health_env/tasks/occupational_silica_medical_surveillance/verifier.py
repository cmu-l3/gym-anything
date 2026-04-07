#!/usr/bin/env python3
"""
Verifier for occupational_silica_medical_surveillance task.

Evaluates an agent's ability to complete a multi-module occupational health baseline
for silica dust exposure in GNU Health.

Scoring breakdown (100 points total):
  - 20 pts: Occupational exposure diagnosis (Z57.x) for John Zenon
  - 20 pts: Clinical evaluation documenting Respiratory Rate and SpO2
  - 20 pts: Lifestyle record added (smoking history)
  - 20 pts: At least 2 baseline lab test orders
  - 20 pts: Annual follow-up appointment within 350-380 days (approx. 1 year)

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_silica_medical_surveillance(traj, env_info, task_info):
    """Verify occupational medical surveillance documentation for patient John Zenon."""
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

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_silica_medical_surveillance_result.json', local_path)
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
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patient John Zenon not found. Setup may have failed.",
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

    # --- Criterion 1: Z57.x Occupational Exposure Diagnosis (20 pts) ---
    z57_found = result.get('z57_found', False)
    z57_active = result.get('z57_active', False)
    z57_code = result.get('z57_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if z57_found:
        score += 20
        subscores['exposure_diagnosis'] = 20
        feedback_parts.append(f"Occupational exposure documented: ICD-10 {z57_code}")
        if not z57_active:
            feedback_parts[-1] += " (Note: Not marked active)"
    elif any_new_disease > 0:
        score += 5
        subscores['exposure_diagnosis'] = 5
        feedback_parts.append("A condition was added but not a Z57.x occupational exposure code")
    else:
        subscores['exposure_diagnosis'] = 0
        feedback_parts.append("MISSING: No occupational exposure diagnosis (Z57.x) found for John Zenon")

    # --- Criterion 2: Clinical Evaluation with RR & SpO2 (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_rr = result.get('evaluation_rr', 'null')
    eval_spo2 = result.get('evaluation_spo2', 'null')

    has_rr = False
    has_spo2 = False
    try:
        if eval_rr != 'null' and float(eval_rr) > 0:
            has_rr = True
        if eval_spo2 != 'null' and float(eval_spo2) > 0:
            has_spo2 = True
    except (ValueError, TypeError):
        pass

    if eval_found and has_rr and has_spo2:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with respiratory vitals: RR={eval_rr}, SpO2={eval_spo2}")
    elif eval_found and (has_rr or has_spo2):
        score += 12
        subscores['clinical_evaluation'] = 12
        feedback_parts.append(f"Evaluation documented with partial vitals: RR={eval_rr}, SpO2={eval_spo2}")
    elif eval_found:
        score += 6
        subscores['clinical_evaluation'] = 6
        feedback_parts.append("Evaluation created but Respiratory Rate and Oxygen Saturation were not documented")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Lifestyle / Smoking History (20 pts) ---
    lifestyle_found = result.get('lifestyle_found', False)
    
    if lifestyle_found:
        score += 20
        subscores['lifestyle_record'] = 20
        feedback_parts.append("Lifestyle/smoking history record documented")
    else:
        subscores['lifestyle_record'] = 0
        feedback_parts.append("MISSING: No lifestyle record found")

    # --- Criterion 4: Baseline Labs >= 2 (20 pts) ---
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
        feedback_parts.append(f"Only 1 baseline lab ordered ({new_lab_types}); standard baseline requires multiple markers")
    else:
        subscores['baseline_labs'] = 0
        feedback_parts.append("MISSING: No baseline laboratory tests ordered")

    # --- Criterion 5: Annual Appointment in ~365 days (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days_diff = result.get('appointment_days_diff', 0)
    try:
        appt_days_diff = int(appt_days_diff)
    except (ValueError, TypeError):
        appt_days_diff = 0

    if appt_found and 350 <= appt_days_diff <= 380:
        score += 20
        subscores['annual_appointment'] = 20
        feedback_parts.append(f"Annual surveillance appointment scheduled successfully in {appt_days_diff} days")
    elif appt_found:
        score += 5
        subscores['annual_appointment'] = 5
        feedback_parts.append(f"Appointment scheduled but interval is incorrect ({appt_days_diff} days instead of ~365)")
    else:
        subscores['annual_appointment'] = 0
        feedback_parts.append("MISSING: No future surveillance appointment scheduled")

    # Calculate final status
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "subscores": subscores
    }