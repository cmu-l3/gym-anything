#!/usr/bin/env python3
"""
Verifier for occupational_radiation_exposure task.

This task requires the agent to coordinate a multi-step ARS triage protocol.

Scoring breakdown (100 points total):
  - 20 pts: Radiation exposure diagnosis (W90.x or Z57.1) for Matt Zenon
  - 20 pts: Clinical evaluation with elevated heart rate (>= 80 bpm)
  - 20 pts: At least 2 baseline lab orders (CBC, BMP, etc.)
  - 20 pts: Antiemetic prescription (Ondansetron/Metoclopramide/Promethazine)
  - 20 pts: Follow-up appointment within 2-7 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_radiation_exposure(traj, env_info, task_info):
    """Verify occupational radiation exposure protocol for patient Matt Zenon."""
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
        copy_from_env('/tmp/occupational_radiation_exposure_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Matt Zenon not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'matt' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Matt Zenon, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Radiation Diagnosis W90/Z57.1 (20 pts) ---
    rad_found = result.get('rad_diagnosis_found', False)
    rad_code = result.get('rad_diagnosis_code', 'none')
    rad_active = result.get('rad_diagnosis_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if rad_found and rad_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Radiation exposure diagnosis documented: ICD-10 {rad_code} (active)")
    elif rad_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Radiation diagnosis {rad_code} found but not marked active")
    elif any_new_disease > 0:
        score += 8
        subscores['diagnosis'] = 8
        feedback_parts.append("A diagnosis was added but not a radiation exposure code (expected W90 or Z57.1)")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No radiation exposure diagnosis for Matt Zenon")

    # --- Criterion 2: Clinical evaluation with elevated heart rate (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_hr = result.get('evaluation_heart_rate', 'N/A')
    eval_hr_elevated = result.get('evaluation_hr_elevated', False)

    if eval_found and eval_hr_elevated:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with elevated HR ({eval_hr} bpm)")
    elif eval_found and eval_hr != 'null':
        score += 12
        subscores['evaluation'] = 12
        feedback_parts.append(f"Evaluation documented but HR is not elevated >= 80 (got {eval_hr})")
    elif eval_found:
        score += 8
        subscores['evaluation'] = 8
        feedback_parts.append("Evaluation created but vital signs (heart rate) not documented")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Baseline Labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Baseline lab panel ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — baseline protocol requires at least 2")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No baseline laboratory workup ordered")

    # --- Criterion 4: Antiemetic Prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    antiemetic_found = result.get('antiemetic_found', False)
    antiemetic_name = result.get('antiemetic_drug_name', 'none')

    if prescription_found and antiemetic_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Antiemetic prescribed: {antiemetic_name}")
    elif prescription_found:
        score += 8
        subscores['prescription'] = 8
        feedback_parts.append("Prescription created but no antiemetic identified (expected Ondansetron/Metoclopramide/Promethazine)")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No antiemetic prescription found")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_in_window = result.get('appointment_in_window', False)
    appt_days_out = result.get('appointment_days_out', '0')

    if appt_found and appt_in_window:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled correctly ({appt_days_out} days out)")
    elif appt_found:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Appointment scheduled but outside 2-7 day window ({appt_days_out} days out)")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Final Score Calculation ---
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }