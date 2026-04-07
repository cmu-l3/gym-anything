#!/usr/bin/env python3
"""
Verifier for occupational_antineoplastic_exposure_protocol task.

This is a very_hard task. The agent must independently manage a workplace
chemical exposure protocol including diagnosis, evaluation, labs, prescription,
and surveillance follow-up.

Scoring breakdown (100 points total):
  - 20 pts: Chemical exposure diagnosis (Z57.x or T45.x) for Ana Betz
  - 20 pts: Clinical evaluation with recorded vitals
  - 20 pts: At least 3 baseline toxicity laboratory orders
  - 20 pts: Topical corticosteroid prescribed for contact dermatitis
  - 20 pts: Surveillance follow-up appointment within 7-14 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_antineoplastic_exposure_protocol(traj, env_info, task_info):
    """Verify occupational antineoplastic exposure protocol for patient Ana Betz."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_antineoplastic_exposure_protocol_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Ana Betz not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'ana' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Ana Betz, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Exposure Diagnosis (20 pts) ---
    exp_found = result.get('exp_found', False)
    exp_active = result.get('exp_active', False)
    exp_code = result.get('exp_code', 'none')
    exp_specific = result.get('exp_specific', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0
        
    if exp_found and exp_active and exp_specific:
        score += 20
        subscores['exposure_diagnosis'] = 20
        feedback_parts.append(f"Exposure diagnosis documented accurately: {exp_code} (active, specific)")
    elif exp_found and exp_active:
        score += 15
        subscores['exposure_diagnosis'] = 15
        feedback_parts.append(f"Exposure diagnosis documented: {exp_code} (active). More specific code preferred.")
    elif exp_found:
        score += 10
        subscores['exposure_diagnosis'] = 10
        feedback_parts.append(f"Exposure diagnosis {exp_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['exposure_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an appropriate exposure code (Z57.x or T45.x expected)")
    else:
        subscores['exposure_diagnosis'] = 0
        feedback_parts.append("MISSING: No occupational exposure diagnosis documented")

    # --- Criterion 2: Clinical Evaluation (20 pts) ---
    eval_found = result.get('eval_found', False)
    eval_temp = result.get('eval_temp', 'N/A')
    eval_hr = result.get('eval_hr', 'N/A')
    eval_sys = result.get('eval_sys', 'N/A')
    
    if eval_found and eval_temp != 'null' and eval_hr != 'null' and eval_sys != 'null':
        score += 20
        subscores['clinical_eval'] = 20
        feedback_parts.append(f"Clinical evaluation recorded with comprehensive vitals (Temp: {eval_temp}, HR: {eval_hr}, Sys: {eval_sys})")
    elif eval_found and (eval_temp != 'null' or eval_hr != 'null' or eval_sys != 'null'):
        score += 12
        subscores['clinical_eval'] = 12
        feedback_parts.append("Clinical evaluation found but vital signs partially missing")
    elif eval_found:
        score += 5
        subscores['clinical_eval'] = 5
        feedback_parts.append("Clinical evaluation found but missing necessary vital signs")
    else:
        subscores['clinical_eval'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Laboratory Orders (20 pts) ---
    lab_count = result.get('new_lab_count', 0)
    try:
        lab_count = int(lab_count)
    except (ValueError, TypeError):
        lab_count = 0
        
    if lab_count >= 3:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Baseline toxicity labs ordered correctly ({lab_count} tests)")
    elif lab_count == 2:
        score += 13
        subscores['lab_orders'] = 13
        feedback_parts.append(f"Only 2 labs ordered, >= 3 expected for comprehensive baseline toxicity panel")
    elif lab_count == 1:
        score += 7
        subscores['lab_orders'] = 7
        feedback_parts.append(f"Only 1 lab ordered, >= 3 expected")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No baseline toxicity labs ordered")

    # --- Criterion 4: Prescription (20 pts) ---
    presc_found = result.get('prescription_found', False)
    corticosteroid_found = result.get('corticosteroid_found', False)
    corticosteroid_name = result.get('corticosteroid_name', 'none')
    
    if presc_found and corticosteroid_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Appropriate topical corticosteroid prescribed: {corticosteroid_name}")
    elif presc_found:
        score += 10
        subscores['prescription'] = 10
        feedback_parts.append("Prescription found but no corticosteroid identified")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No prescription found for contact dermatitis treatment")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_days = result.get('appt_days_diff', 0)
    try:
        appt_days = int(appt_days)
    except (ValueError, TypeError):
        appt_days = 0
        
    if appt_found and 7 <= appt_days <= 14:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Surveillance follow-up correctly scheduled in {appt_days} days")
    elif appt_found and (0 < appt_days <= 30):
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up appointment scheduled but outside 7-14 day window ({appt_days} days)")
    elif appt_found:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append("Follow-up appointment found but invalid date")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }