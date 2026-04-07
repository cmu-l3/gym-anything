#!/usr/bin/env python3
"""
Verifier for occupational_hydrofluoric_acid_exposure task.

This task evaluates the documentation and acute management of a highly
specific chemical burn requiring immediate antidote prescribing.

Scoring breakdown (100 points total):
  - 20 pts: T54.2 or T22 ICD-10 diagnosis documented for John Zenon
  - 20 pts: Clinical evaluation with Tachycardia (HR >= 100)
  - 20 pts: Prescription specifically containing Calcium Gluconate (CRITICAL)
  - 20 pts: At least 2 lab orders including systemic Calcium/CMP monitoring
  - 20 pts: Appointment scheduled exactly 1 day from the current system date

Pass threshold: score >= 70 AND Calcium Gluconate Rx is mandatory.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_hydrofluoric_acid_exposure(traj, env_info, task_info):
    """Verify occupational hydrofluoric acid exposure protocol."""
    copy_from_env = env_info.get('copy_from_env')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_hydrofluoric_acid_exposure_result.json', local_path)
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

    # --- Criterion 1: Toxic/Burn Diagnosis T-code (20 pts) ---
    t_found = result.get('t_code_found', False)
    t_code = result.get('t_code', 'none')
    t_active = result.get('t_code_active', False)
    t54_t22_specific = result.get('t54_t22_specific', False)

    if t_found and t_active and t54_t22_specific:
        score += 20
        subscores['hf_diagnosis'] = 20
        feedback_parts.append(f"HF specific diagnosis documented: ICD-10 {t_code} (active)")
    elif t_found and t_active:
        score += 15
        subscores['hf_diagnosis'] = 15
        feedback_parts.append(f"T-code injury documented: {t_code} (active) — T54.x or T22.x preferred for HF burns")
    elif t_found:
        score += 10
        subscores['hf_diagnosis'] = 10
        feedback_parts.append(f"T-code found ({t_code}) but not marked active")
    else:
        subscores['hf_diagnosis'] = 0
        feedback_parts.append("MISSING: No toxicological/burn diagnosis (T-code) found for John Zenon")

    # --- Criterion 2: Clinical evaluation with Tachycardia (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_hr = result.get('evaluation_heart_rate', 'N/A')
    eval_has_tachycardia = result.get('evaluation_has_tachycardia', False)

    if eval_found and eval_has_tachycardia:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with tachycardia (HR={eval_hr})")
    elif eval_found:
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append(f"Evaluation created but HR ({eval_hr}) does not reflect acute pain response (needs >= 100)")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Calcium Gluconate Rx (20 pts) - CRITICAL MANDATORY ---
    prescription_found = result.get('prescription_found', False)
    calcium_rx_found = result.get('calcium_rx_found', False)
    calcium_rx_name = result.get('calcium_rx_name', 'none')

    if prescription_found and calcium_rx_found:
        score += 20
        subscores['antidote_rx'] = 20
        feedback_parts.append(f"Antidote prescribed successfully: {calcium_rx_name}")
    elif prescription_found:
        subscores['antidote_rx'] = 0
        feedback_parts.append("CRITICAL FAILURE: A prescription was created, but Calcium Gluconate (the mandatory HF antidote) was NOT included.")
    else:
        subscores['antidote_rx'] = 0
        feedback_parts.append("CRITICAL FAILURE: No prescriptions created. HF exposure mandates immediate Calcium Gluconate.")

    # --- Criterion 4: Systemic Toxicity Lab Panel (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    calcium_lab_found = result.get('calcium_lab_found', False)
    
    try:
        new_lab_count = int(new_lab_count)
    except:
        new_lab_count = 0

    if new_lab_count >= 2 and calcium_lab_found:
        score += 20
        subscores['hf_labs'] = 20
        feedback_parts.append(f"Targeted lab panel ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count >= 2:
        score += 10
        subscores['hf_labs'] = 10
        feedback_parts.append(f"Lab tests ordered ({new_lab_types}) but missing specific Calcium/CMP monitoring")
    elif new_lab_count == 1:
        score += 5
        subscores['hf_labs'] = 5
        feedback_parts.append(f"Only 1 lab test ordered ({new_lab_types}). Minimum 2 required.")
    else:
        subscores['hf_labs'] = 0
        feedback_parts.append("MISSING: No lab orders created for systemic monitoring")

    # --- Criterion 5: 1-Day Wound Reassessment Follow-up (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_date = result.get('appt_date', 'null')
    appt_is_1_day = result.get('appt_is_1_day', False)

    if appt_found and appt_is_1_day:
        score += 20
        subscores['follow_up'] = 20
        feedback_parts.append(f"1-day wound reassessment scheduled correctly ({appt_date})")
    elif appt_found:
        score += 10
        subscores['follow_up'] = 10
        feedback_parts.append(f"Appointment scheduled for {appt_date}, but HF protocol requires exactly 1-day follow-up")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Final Score Resolution ---
    # Due to the high mortality risk of HF burns, failing to prescribe the antidote prevents a passing score.
    passed = (score >= 70) and calcium_rx_found

    if score >= 70 and not calcium_rx_found:
        feedback_parts.append("TASK FAILED: Regardless of other documentation, failing to prescribe Calcium Gluconate for an HF burn is a fatal clinical error.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }