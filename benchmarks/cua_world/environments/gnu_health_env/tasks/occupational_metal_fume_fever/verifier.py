#!/usr/bin/env python3
"""
Verifier for occupational_metal_fume_fever task.

This task requires the agent to document an acute episode of metal fume fever.
Scoring breakdown (100 points total):
  - 20 pts: Inhalation Diagnosis (J68 or T59 family) for John Zenon
  - 20 pts: Febrile Evaluation (clinical evaluation with Temp >= 38.5 °C)
  - 20 pts: Antipyretic Rx (Ibuprofen, Paracetamol, or Acetaminophen)
  - 20 pts: Diagnostic Orders (at least 2 lab/imaging tests ordered)
  - 20 pts: Rapid Follow-up (appointment scheduled in 1 to 3 days)

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_metal_fume_fever(traj, env_info, task_info):
    """Verify occupational metal fume fever documentation for patient John Zenon."""
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
        copy_from_env('/tmp/occupational_metal_fume_fever_result.json', local_path)
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

    # CRITICAL CHECK: Correct target patient
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patient John Zenon not found — setup may have failed.",
            "subscores": {}
        }

    # --- Criterion 1: Inhalation Diagnosis (20 pts) ---
    inhalation_found = result.get('inhalation_found', False)
    inhalation_active = result.get('inhalation_active', False)
    inhalation_code = result.get('inhalation_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if inhalation_found and inhalation_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Inhalation diagnosis documented: ICD-10 {inhalation_code} (active)")
    elif inhalation_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Inhalation diagnosis found ({inhalation_code}) but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but not a J68/T59 inhalation/toxic effect code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No inhalation/toxic effect diagnosis for John Zenon")

    # --- Criterion 2: Febrile Evaluation (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_temp = result.get('evaluation_temperature', 'N/A')
    eval_has_fever = result.get('evaluation_has_fever', False)

    if eval_found and eval_has_fever:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with fever: {eval_temp} °C")
    elif eval_found:
        score += 10
        subscores['evaluation'] = 10
        feedback_parts.append(f"Clinical evaluation created but fever not correctly documented (got {eval_temp} °C, expected >= 38.5)")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Antipyretic Rx (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    antipyretic_found = result.get('antipyretic_found', False)
    antipyretic_name = result.get('antipyretic_name', 'none')

    if prescription_found and antipyretic_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Symptomatic relief prescribed: {antipyretic_name}")
    elif prescription_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but no matching antipyretic (Ibuprofen/Paracetamol/Acetaminophen) found")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No prescription order documented")

    # --- Criterion 4: Diagnostic Orders >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['diagnostics'] = 20
        feedback_parts.append(f"Appropriate diagnostic workup: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['diagnostics'] = 10
        feedback_parts.append(f"Only 1 diagnostic test ordered ({new_lab_types}), expected at least 2")
    else:
        subscores['diagnostics'] = 0
        feedback_parts.append("MISSING: No diagnostic tests/labs ordered")

    # --- Criterion 5: Rapid Follow-up Appointment (20 pts) ---
    followup_found = result.get('followup_found', False)
    followup_date = result.get('followup_date', 'none')
    any_new_appt = result.get('any_new_appt_count', 0)
    try:
        any_new_appt = int(any_new_appt)
    except (ValueError, TypeError):
        any_new_appt = 0

    if followup_found:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Short-interval follow-up appointment correctly scheduled: {followup_date}")
    elif any_new_appt > 0:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append("An appointment was scheduled, but the date is outside the 1-3 day window required for metal fume fever")
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