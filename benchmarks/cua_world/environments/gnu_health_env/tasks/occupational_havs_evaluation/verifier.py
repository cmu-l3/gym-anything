#!/usr/bin/env python3
"""
Verifier for occupational_havs_evaluation task.

This task evaluates the documentation of Hand-Arm Vibration Syndrome (HAVS)
and management of secondary autoimmune rule-out workflows.

Scoring breakdown (100 points total):
  - 20 pts: HAVS/Raynaud's diagnosis (T75.2 or I73.0) for John Zenon
  - 20 pts: Clinical evaluation/encounter record
  - 20 pts: Vasodilator prescription (Nifedipine or Amlodipine)
  - 20 pts: At least 2 lab orders to rule out systemic causes
  - 20 pts: Follow-up appointment within 21-45 days

Pass threshold: score >= 60
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_havs_evaluation(traj, env_info, task_info):
    """Verify occupational HAVS evaluation protocol for patient John Zenon."""
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
        copy_from_env('/tmp/occupational_havs_evaluation_result.json', local_path)
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
    if 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: HAVS Diagnosis (20 pts) ---
    havs_found = result.get('havs_diagnosis_found', False)
    havs_active = result.get('havs_diagnosis_active', False)
    havs_code = result.get('havs_diagnosis_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if havs_found and havs_active:
        score += 20
        subscores['havs_diagnosis'] = 20
        feedback_parts.append(f"Occupational HAVS diagnosis documented: ICD-10 {havs_code} (active)")
    elif havs_found:
        score += 15
        subscores['havs_diagnosis'] = 15
        feedback_parts.append(f"HAVS diagnosis {havs_code} found but not marked active")
    elif any_new_disease > 0:
        score += 8
        subscores['havs_diagnosis'] = 8
        feedback_parts.append(f"A diagnosis was added but not a vibration-specific T75.2 or Raynaud's I73.0 code")
    else:
        subscores['havs_diagnosis'] = 0
        feedback_parts.append("MISSING: No occupational HAVS diagnosis for John Zenon")

    # --- Criterion 2: Clinical Evaluation (20 pts) ---
    eval_found = result.get('evaluation_found', False)

    if eval_found:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append("Clinical evaluation/encounter documented")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Vasodilator Prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    vaso_found = result.get('vasodilator_found', False)
    vaso_name = result.get('vasodilator_name', 'none')

    if prescription_found and vaso_found:
        score += 20
        subscores['vasodilator_prescription'] = 20
        feedback_parts.append(f"Vasodilator prescribed: {vaso_name}")
    elif prescription_found:
        score += 10
        subscores['vasodilator_prescription'] = 10
        feedback_parts.append("Prescription created but NOT for expected vasodilator (Nifedipine/Amlodipine)")
    else:
        subscores['vasodilator_prescription'] = 0
        feedback_parts.append("MISSING: No medications prescribed")

    # --- Criterion 4: Laboratory Orders (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Adequate lab orders placed to rule out systemic causes ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['lab_orders'] = 10
        feedback_parts.append(f"Only 1 lab test ordered ({new_lab_types}). Expected at least 2 for comprehensive rule-out")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No laboratory tests ordered")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days = result.get('appointment_days_diff', 0)
    try:
        appt_days = int(appt_days)
    except (ValueError, TypeError):
        appt_days = 0

    if appt_found and 21 <= appt_days <= 45:
        score += 20
        subscores['followup_appointment'] = 20
        feedback_parts.append(f"Follow-up scheduled correctly ({appt_days} days out)")
    elif appt_found:
        score += 10
        subscores['followup_appointment'] = 10
        feedback_parts.append(f"Follow-up scheduled, but timeframe ({appt_days} days) is outside the 21-45 day window")
    else:
        subscores['followup_appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Final Result ---
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }