#!/usr/bin/env python3
"""
Verifier for bloodborne_pathogen_pep task.

Scoring breakdown (100 points total):
  - 25 pts: Exposure/Needlestick diagnosis (W46 or Z20)
  - 25 pts: At least 2 baseline serology labs ordered
  - 25 pts: Antiretroviral PEP prescription
  - 25 pts: Follow-up appointment scheduled in 28-35 days

Pass threshold: score >= 75
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_bloodborne_pathogen_pep(traj, env_info, task_info):
    """Verify PEP protocol for John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/bloodborne_pathogen_pep_result.json', local_path)
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
    if 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # Criterion 1: Exposure diagnosis (25 pts)
    exposure_found = result.get('exposure_found', False)
    exposure_active = result.get('exposure_active', False)
    exposure_code = result.get('exposure_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if exposure_found and exposure_active:
        score += 25
        subscores['exposure_diagnosis'] = 25
        feedback_parts.append(f"Exposure diagnosis documented: ICD-10 {exposure_code} (active)")
    elif exposure_found:
        score += 15
        subscores['exposure_diagnosis'] = 15
        feedback_parts.append(f"Exposure diagnosis found ({exposure_code}) but NOT marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['exposure_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a Needlestick/Exposure code (W46/Z20)")
    else:
        subscores['exposure_diagnosis'] = 0
        feedback_parts.append("MISSING: No exposure diagnosis (W46/Z20) found")

    # Criterion 2: Baseline Labs >= 2 (25 pts)
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 25
        subscores['baseline_labs'] = 25
        feedback_parts.append(f"Baseline labs ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['baseline_labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — PEP requires at least 2 baseline serology tests")
    else:
        subscores['baseline_labs'] = 0
        feedback_parts.append("MISSING: No baseline labs ordered")

    # Criterion 3: PEP Prescription (25 pts)
    presc_found = result.get('prescription_found', False)
    pep_drug_found = result.get('pep_drug_found', False)
    pep_drug_name = result.get('pep_drug_name', 'none')

    if presc_found and pep_drug_found:
        score += 25
        subscores['pep_prescription'] = 25
        feedback_parts.append(f"Antiretroviral PEP prescribed: {pep_drug_name}")
    elif presc_found:
        score += 10
        subscores['pep_prescription'] = 10
        feedback_parts.append("Prescription created but no suitable antiretroviral/PEP medication identified")
    else:
        subscores['pep_prescription'] = 0
        feedback_parts.append("MISSING: No prescription created for PEP")

    # Criterion 4: Follow-up Appointment 28-35 days (25 pts)
    appt_found = result.get('appointment_found', False)
    appt_date = result.get('appointment_date', 'none')
    appt_days_delta = result.get('appointment_days_delta', 0)
    try:
        appt_days_delta = int(appt_days_delta)
    except (ValueError, TypeError):
        appt_days_delta = 0

    if appt_found:
        if 28 <= appt_days_delta <= 35:
            score += 25
            subscores['followup_appointment'] = 25
            feedback_parts.append(f"Follow-up appointment scheduled appropriately: {appt_date} ({appt_days_delta} days)")
        else:
            score += 10
            subscores['followup_appointment'] = 10
            feedback_parts.append(f"Follow-up appointment scheduled at {appt_date} ({appt_days_delta} days), but should be 28-35 days (4 weeks) post-exposure")
    else:
        subscores['followup_appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }