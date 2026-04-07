#!/usr/bin/env python3
"""
Verifier for industrial_hexavalent_chromium_exposure task.

Scoring breakdown (100 points total):
  - 20 pts: T56.2 Chromium toxicity diagnosis (active) for Roberto Carlos
  - 20 pts: Clinical evaluation with precise Temp (37.0) and HR (75)
  - 20 pts: Prescription for Ascorbic Acid, Mupirocin, or Bacitracin
  - 20 pts: At least 2 lab orders
  - 20 pts: Follow-up appointment scheduled 10-20 days from today

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_industrial_hexavalent_chromium_exposure(traj, env_info, task_info):
    """Verify chromium exposure workflow for patient Roberto Carlos."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/industrial_hexavalent_chromium_exposure_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Roberto Carlos not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'roberto' not in target_name.lower() or 'carlos' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Roberto Carlos, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: T56.2 Diagnosis (20 pts) ---
    t56_found = result.get('t56_found', False)
    t56_active = result.get('t56_active', False)
    t56_exact = result.get('t56_exact', False)
    t56_code = result.get('t56_code', 'none')
    any_disease = int(result.get('any_new_disease_count', 0))

    if t56_found and t56_active and t56_exact:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Diagnosis correct: {t56_code} (active)")
    elif t56_found and t56_active:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"T56.x code recorded ({t56_code}, active) but missing exact T56.2 specification")
    elif t56_found:
        score += 10
        subscores['diagnosis'] = 10
        feedback_parts.append(f"T56.x code found ({t56_code}) but not marked active")
    elif any_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but not a Chromium toxicity T-code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No new diagnosis recorded")

    # --- Criterion 2: Clinical Evaluation (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_temp = result.get('evaluation_temperature', 'null')
    eval_hr = result.get('evaluation_heart_rate', 'null')
    
    if eval_found:
        temp_ok = False
        try:
            if float(eval_temp) == 37.0:
                temp_ok = True
        except:
            pass
            
        hr_ok = str(eval_hr).strip() == "75"
        
        if temp_ok and hr_ok:
            score += 20
            subscores['evaluation'] = 20
            feedback_parts.append(f"Evaluation perfectly documented: Temp {eval_temp}, HR {eval_hr}")
        elif temp_ok or hr_ok:
            score += 10
            subscores['evaluation'] = 10
            feedback_parts.append(f"Evaluation documented, but missing one vital: Temp {eval_temp}, HR {eval_hr}")
        else:
            score += 5
            subscores['evaluation'] = 5
            feedback_parts.append(f"Evaluation documented, but wrong vitals: Temp {eval_temp}, HR {eval_hr}")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No evaluation created")

    # --- Criterion 3: Targeted Prescription (20 pts) ---
    presc_found = result.get('prescription_found', False)
    target_rx_found = result.get('target_rx_found', False)
    rx_name = result.get('target_rx_name', 'none')

    if presc_found and target_rx_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Prescription recorded: {rx_name}")
    elif presc_found:
        score += 10
        subscores['prescription'] = 10
        feedback_parts.append("Prescription created, but not the targeted therapy (Ascorbic Acid, Mupirocin, Bacitracin)")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No prescription recorded")

    # --- Criterion 4: Laboratory Orders (20 pts) ---
    lab_count = int(result.get('new_lab_count', 0))
    lab_types = result.get('new_lab_types', '')
    
    if lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Lab orders recorded ({lab_count}): {lab_types}")
    elif lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Only 1 lab order recorded: {lab_types}")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No lab orders recorded")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days = int(result.get('appointment_days_out', 0))
    appt_date = result.get('appointment_date', 'null')
    
    if appt_found:
        if 10 <= appt_days <= 20:
            score += 20
            subscores['appointment'] = 20
            feedback_parts.append(f"Follow-up scheduled correctly ({appt_days} days out: {appt_date})")
        else:
            score += 10
            subscores['appointment'] = 10
            feedback_parts.append(f"Follow-up scheduled, but {appt_days} days out instead of 10-20 (Date: {appt_date})")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Final Result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores
    }