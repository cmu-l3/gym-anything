#!/usr/bin/env python3
"""
Verifier for occupational_berylliosis_surveillance task.

Scoring breakdown (100 points total):
  - 20 pts: Berylliosis diagnosis (J63.2) for John Zenon
  - 20 pts: Clinical evaluation documenting Oxygen Saturation (SpO2) 88-92%
  - 20 pts: Corticosteroid prescription (Prednisone/Dexamethasone/etc.)
  - 20 pts: At least 2 baseline laboratory orders
  - 20 pts: Follow-up appointment scheduled within 30-45 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_berylliosis_surveillance(traj, env_info, task_info):
    """Verify occupational Berylliosis surveillance protocol."""
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
        copy_from_env('/tmp/occupational_berylliosis_surveillance_result.json', local_path)
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
    target_id = result.get('target_patient_id', "0")
    if not target_id or str(target_id) == "0":
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

    # Criterion 1: J63.2 Berylliosis Diagnosis (20 pts)
    j63_found = result.get('j63_found', False)
    j63_active = result.get('j63_active', False)
    j63_code = result.get('j63_code', 'none')
    try:
        any_new_disease = int(result.get('any_new_disease_count', 0))
    except (ValueError, TypeError):
        any_new_disease = 0

    if j63_found and j63_active and j63_code == "J63.2":
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Diagnosis documented: ICD-10 {j63_code} (active)")
    elif j63_found and j63_active:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"J63.x diagnosis found: {j63_code} (active) — Expected exact J63.2 Berylliosis")
    elif j63_found:
        score += 10
        subscores['diagnosis'] = 10
        feedback_parts.append(f"J63.x diagnosis found ({j63_code}) but NOT marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but not J63.x Berylliosis")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No Berylliosis diagnosis (J63.2) found for John Zenon")

    # Criterion 2: Clinical Evaluation with Oxygen Saturation (20 pts)
    eval_found = result.get('evaluation_found', False)
    eval_osat_str = result.get('evaluation_osat', 'null')
    
    if eval_found and eval_osat_str != 'null':
        try:
            osat_val = float(eval_osat_str)
            if 88 <= osat_val <= 92:
                score += 20
                subscores['evaluation'] = 20
                feedback_parts.append(f"Evaluation documented with correct SpO2: {osat_val}%")
            else:
                score += 12
                subscores['evaluation'] = 12
                feedback_parts.append(f"Evaluation documented, but SpO2 {osat_val}% is outside required 88-92% range")
        except ValueError:
            score += 8
            subscores['evaluation'] = 8
            feedback_parts.append(f"Evaluation found but SpO2 value '{eval_osat_str}' is invalid")
    elif eval_found:
        score += 5
        subscores['evaluation'] = 5
        feedback_parts.append("Evaluation created, but Oxygen Saturation (SpO2) was not documented")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 3: Corticosteroid Prescription (20 pts)
    prescription_found = result.get('prescription_found', False)
    corticosteroid_found = result.get('corticosteroid_found', False)
    drug_name = result.get('corticosteroid_drug_name', 'none')

    if prescription_found and corticosteroid_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Corticosteroid prescribed: {drug_name}")
    elif prescription_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but no corticosteroid (Prednisone/Dexamethasone) identified")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No corticosteroid prescription created")

    # Criterion 4: Baseline Labs >= 2 (20 pts)
    try:
        new_lab_count = int(result.get('new_lab_count', 0))
    except (ValueError, TypeError):
        new_lab_count = 0
    lab_types = result.get('new_lab_types', '')

    if new_lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Sufficient lab orders created: {new_lab_count} ({lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({lab_types}). Task requires at least 2.")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No laboratory baseline tests ordered")

    # Criterion 5: Follow-up Appointment 30-45 days (20 pts)
    appt_found = result.get('appointment_found', False)
    try:
        appt_days_diff = int(result.get('appointment_days_diff', -999))
    except (ValueError, TypeError):
        appt_days_diff = -999

    if appt_found:
        if 30 <= appt_days_diff <= 45:
            score += 20
            subscores['appointment'] = 20
            feedback_parts.append(f"Follow-up appointment scheduled in {appt_days_diff} days (correct window)")
        elif appt_days_diff >= 0:
            score += 10
            subscores['appointment'] = 10
            feedback_parts.append(f"Appointment scheduled in {appt_days_diff} days (outside 30-45 day window)")
        else:
            score += 5
            subscores['appointment'] = 5
            feedback_parts.append(f"Appointment scheduled in past or invalid date: {appt_days_diff}")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # Final verdict
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }