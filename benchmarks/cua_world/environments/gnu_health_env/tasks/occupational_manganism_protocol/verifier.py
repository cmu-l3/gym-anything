#!/usr/bin/env python3
"""
Verifier for occupational_manganism_protocol task.

Scoring breakdown (100 points total):
  - 20 pts: Manganism diagnosis (G21.x or T56.x) for John Zenon
  - 20 pts: Clinical evaluation with elevated heart rate (>=90) AND specific note
  - 20 pts: At least 2 diagnostic lab/imaging orders
  - 20 pts: Levodopa trial prescription
  - 20 pts: Follow-up appointment within 14-30 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_manganism_protocol(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_manganism_protocol_result.json', local_path)
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

    target_id = result.get('target_patient_id', "0")
    if str(target_id) == "0" or not target_id:
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

    # Criterion 1: Diagnosis
    disease_found = result.get('disease_found', False)
    disease_active = result.get('disease_active', False)
    disease_code = result.get('disease_code', 'none')
    any_disease = result.get('any_new_disease_count', 0)

    if disease_found and disease_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Manganism diagnosis documented: {disease_code} (active)")
    elif disease_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Manganism diagnosis found ({disease_code}) but not marked active")
    elif any_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a G21 or T56 code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No Manganism diagnosis (G21.x/T56.x) for John Zenon")

    # Criterion 2: Clinical Evaluation
    eval_found = result.get('evaluation_found', False)
    eval_hr = result.get('evaluation_heart_rate', 'N/A')
    has_tachycardia = result.get('evaluation_has_tachycardia', False)
    has_note = result.get('evaluation_has_note', False)

    if eval_found and has_tachycardia and has_note:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append(f"Evaluation documented with HR={eval_hr} and key clinical notes")
    elif eval_found and has_tachycardia:
        score += 15
        subscores['evaluation'] = 15
        feedback_parts.append(f"Evaluation has HR={eval_hr} but missing required keyword in notes")
    elif eval_found and has_note:
        score += 15
        subscores['evaluation'] = 15
        feedback_parts.append(f"Evaluation has clinical notes but HR was not elevated (HR={eval_hr})")
    elif eval_found:
        score += 5
        subscores['evaluation'] = 5
        feedback_parts.append("Evaluation created but lacking elevated HR and clinical notes")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 3: Labs
    lab_count = int(result.get('new_lab_count', 0))
    lab_types = result.get('new_lab_types', '')

    if lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Diagnostic labs ordered: {lab_count} ({lab_types})")
    elif lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Only 1 diagnostic order found ({lab_types})")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No diagnostic labs ordered")

    # Criterion 4: Prescription
    presc_found = result.get('prescription_found', False)
    levodopa_found = result.get('levodopa_found', False)
    levodopa_name = result.get('levodopa_name', 'none')

    if presc_found and levodopa_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Levodopa trial prescribed: {levodopa_name}")
    elif presc_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but Levodopa/Carbidopa was not prescribed")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No levodopa trial prescribed")

    # Criterion 5: Appointment
    appt_found = result.get('appointment_found', False)
    appt_days = int(result.get('appointment_days_diff', -1))

    if appt_found and 14 <= appt_days <= 30:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Follow-up scheduled correctly ({appt_days} days)")
    elif appt_found:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up scheduled but outside 14-30 day window ({appt_days} days)")
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