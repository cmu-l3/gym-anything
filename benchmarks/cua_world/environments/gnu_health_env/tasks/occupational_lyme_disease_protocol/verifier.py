#!/usr/bin/env python3
"""
Verifier for occupational_lyme_disease_protocol task.

This task requires the agent to document an occupational biological exposure
(Lyme disease) across multiple GNU Health modules (conditions, evaluations,
prescriptions, labs, and appointments).

Scoring breakdown (100 points total):
  - 20 pts: Lyme disease diagnosis (A69.2) active for John Zenon
  - 20 pts: Clinical evaluation with temperature >= 37.5C
  - 20 pts: Prescription for Doxycycline/Amoxicillin/Cefuroxime
  - 20 pts: At least 1 new laboratory order
  - 20 pts: Follow-up appointment within 14-28 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_lyme_disease_protocol(traj, env_info, task_info):
    """Verify occupational Lyme disease protocol for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_lyme_disease_protocol_result.json', local_path)
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

    # Criterion 1: A69.2 Lyme disease diagnosis (20 pts)
    a69_found = result.get('a69_found', False)
    a69_active = result.get('a69_active', False)
    a69_code = result.get('a69_code', 'none')
    a692_specific = result.get('a692_specific', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if a69_found and a69_active and a692_specific:
        score += 20
        subscores['lyme_diagnosis'] = 20
        feedback_parts.append(f"Lyme disease diagnosis documented: ICD-10 {a69_code} (active)")
    elif a69_found and a69_active:
        score += 15
        subscores['lyme_diagnosis'] = 15
        feedback_parts.append(f"Lyme diagnosis {a69_code} found (active) — A69.2 would be more specific")
    elif a69_found:
        score += 10
        subscores['lyme_diagnosis'] = 10
        feedback_parts.append(f"Lyme diagnosis {a69_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['lyme_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an A69.x code")
    else:
        subscores['lyme_diagnosis'] = 0
        feedback_parts.append("MISSING: No Lyme disease diagnosis (A69.2) for John Zenon")

    # Criterion 2: Clinical evaluation with fever (20 pts)
    eval_found = result.get('evaluation_found', False)
    eval_has_fever = result.get('evaluation_has_fever', False)
    eval_temp = result.get('evaluation_temperature', 'N/A')

    if eval_found and eval_has_fever:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with low-grade fever: temp={eval_temp}C")
    elif eval_found and eval_temp != 'null':
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append(f"Evaluation documented, but temperature {eval_temp}C does not meet fever threshold (>= 37.5C)")
    elif eval_found:
        score += 5
        subscores['clinical_evaluation'] = 5
        feedback_parts.append("Evaluation created but temperature not documented")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 3: Antibiotic Prescription (20 pts)
    prescription_found = result.get('prescription_found', False)
    antibiotic_found = result.get('antibiotic_found', False)
    antibiotic_name = result.get('antibiotic_name', 'none')

    if prescription_found and antibiotic_found:
        score += 20
        subscores['antibiotic_prescription'] = 20
        feedback_parts.append(f"Antibiotic prescribed: {antibiotic_name}")
    elif prescription_found:
        score += 5
        subscores['antibiotic_prescription'] = 5
        feedback_parts.append("Prescription created but no appropriate antibiotic (Doxycycline/Amoxicillin/Cefuroxime) found")
    else:
        subscores['antibiotic_prescription'] = 0
        feedback_parts.append("MISSING: No appropriate antibiotic prescription")

    # Criterion 4: Laboratory Orders (20 pts)
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 1:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Laboratory order created ({new_lab_types})")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No lab test ordered")

    # Criterion 5: Follow-up Appointment (20 pts)
    appt_found = result.get('appointment_found', False)
    appt_days_str = result.get('appointment_days', '0')
    
    try:
        appt_days = int(float(appt_days_str))
    except (ValueError, TypeError):
        appt_days = 0

    if appt_found and 14 <= appt_days <= 28:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled {appt_days} days out")
    elif appt_found and appt_days > 0:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Appointment scheduled {appt_days} days out (expected 14-28 days)")
    elif appt_found:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append("Appointment scheduled but date is missing or invalid")
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