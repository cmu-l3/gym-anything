#!/usr/bin/env python3
"""
Verifier for agricultural_zoonotic_brucellosis task.

Scoring breakdown (100 points total):
  - 20 pts: Brucellosis diagnosis (A23.x) for John Zenon
  - 20 pts: Clinical evaluation documenting fever >= 38.0
  - 20 pts: Prescription containing Doxycycline AND Rifampicin
  - 20 pts: At least 3 lab orders
  - 20 pts: Follow-up appointment within 28-45 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_agricultural_zoonotic_brucellosis(traj, env_info, task_info):
    """Verify Brucellosis protocol for patient John Zenon."""
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
        copy_from_env('/tmp/agricultural_zoonotic_brucellosis_result.json', local_path)
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
    if 'john' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Brucellosis diagnosis A23.x (20 pts) ---
    a23_found = result.get('a23_found', False)
    a23_active = result.get('a23_active', False)
    a23_code = result.get('a23_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if a23_found and a23_active:
        score += 20
        subscores['brucellosis_diagnosis'] = 20
        feedback_parts.append(f"Brucellosis diagnosis documented: ICD-10 {a23_code} (active)")
    elif a23_found:
        score += 15
        subscores['brucellosis_diagnosis'] = 15
        feedback_parts.append(f"A23 Brucellosis found but NOT marked active — partial credit (code: {a23_code})")
    elif any_new_disease > 0:
        score += 5
        subscores['brucellosis_diagnosis'] = 5
        feedback_parts.append(f"A diagnosis was added but not a Brucellosis A23.x code")
    else:
        subscores['brucellosis_diagnosis'] = 0
        feedback_parts.append("MISSING: No Brucellosis diagnosis (A23.x) found for John Zenon")

    # --- Criterion 2: Clinical evaluation with fever (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_has_fever = result.get('evaluation_has_fever', False)
    eval_temp = result.get('evaluation_temperature', 'N/A')

    if eval_found and eval_has_fever:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented: temp={eval_temp}C (fever)")
    elif eval_found:
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append(f"Evaluation created but temperature={eval_temp}C is not considered a fever (>=38.0)")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for John Zenon")

    # --- Criterion 3: Dual Antibiotic Prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    doxy_found = result.get('doxycycline_found', False)
    rif_found = result.get('rifampicin_found', False)

    if prescription_found and doxy_found and rif_found:
        score += 20
        subscores['dual_antibiotic'] = 20
        feedback_parts.append("Dual antibiotic therapy prescribed: Doxycycline + Rifampicin")
    elif prescription_found and (doxy_found or rif_found):
        score += 10
        subscores['dual_antibiotic'] = 10
        found_drug = "Doxycycline" if doxy_found else "Rifampicin"
        feedback_parts.append(f"Incomplete therapy: Only {found_drug} prescribed. Brucellosis requires dual therapy.")
    elif prescription_found:
        score += 5
        subscores['dual_antibiotic'] = 5
        feedback_parts.append("Prescription created but neither Doxycycline nor Rifampicin found.")
    else:
        subscores['dual_antibiotic'] = 0
        feedback_parts.append("MISSING: No prescription created for the patient.")

    # --- Criterion 4: Baseline Labs >= 3 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 3:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Labs ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 2:
        score += 13
        subscores['lab_orders'] = 13
        feedback_parts.append(f"Only 2 labs ordered ({new_lab_types}) — expected at least 3")
    elif new_lab_count == 1:
        score += 7
        subscores['lab_orders'] = 7
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — insufficient")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No laboratory tests ordered")

    # --- Criterion 5: Follow-up Appointment 28-45 days (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_days_out = result.get('appt_days_out', 0)
    try:
        appt_days_out = int(appt_days_out)
    except (ValueError, TypeError):
        appt_days_out = 0

    if appt_found:
        if 28 <= appt_days_out <= 45:
            score += 20
            subscores['followup_appt'] = 20
            feedback_parts.append(f"Follow-up scheduled correctly: {appt_days_out} days out (within 28-45 day window)")
        else:
            score += 10
            subscores['followup_appt'] = 10
            feedback_parts.append(f"Follow-up scheduled but timing incorrect: {appt_days_out} days out (expected 28-45 days)")
    else:
        subscores['followup_appt'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }