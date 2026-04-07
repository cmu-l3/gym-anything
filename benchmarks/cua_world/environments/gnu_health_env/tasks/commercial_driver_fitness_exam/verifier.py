#!/usr/bin/env python3
"""
Verifier for commercial_driver_fitness_exam task.

Scoring breakdown (100 points total):
  - 20 pts: Clinical Evaluation with BP >= 160/90
  - 20 pts: Hypertension Diagnosis (I10)
  - 20 pts: Sleep Apnea Diagnosis (G47.x)
  - 20 pts: Antihypertensive Prescription (Amlodipine, Lisinopril, or Losartan)
  - 20 pts: Follow-up appointment scheduled within 14-30 days

Pass threshold: score >= 70 AND at least Clinical Evaluation + 1 diagnosis.
"""

import json
import logging
import os
import tempfile
import datetime

logger = logging.getLogger(__name__)


def verify_commercial_driver_fitness_exam(traj, env_info, task_info):
    """Verify commercial driver fitness exam protocol for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/commercial_driver_fitness_result.json', local_path)
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

    # --- Criterion 1: Clinical evaluation with elevated BP (20 pts) ---
    eval_found = result.get('eval_found', False)
    eval_sys_str = result.get('eval_sys', 'null')
    eval_dia_str = result.get('eval_dia', 'null')
    
    sys_val, dia_val = 0.0, 0.0
    try:
        if eval_sys_str != 'null': sys_val = float(eval_sys_str)
        if eval_dia_str != 'null': dia_val = float(eval_dia_str)
    except ValueError:
        pass

    if eval_found and sys_val >= 160.0 and dia_val >= 90.0:
        score += 20
        subscores['clinical_eval'] = 20
        feedback_parts.append(f"Clinical evaluation documented with hypertensive vitals (BP {sys_val}/{dia_val})")
    elif eval_found and (sys_val > 0 or dia_val > 0):
        score += 10
        subscores['clinical_eval'] = 10
        feedback_parts.append(f"Clinical evaluation created but BP {sys_val}/{dia_val} did not meet 160/90 threshold")
    else:
        subscores['clinical_eval'] = 0
        feedback_parts.append("MISSING: No clinical evaluation with BP recorded")

    # --- Criterion 2: I10 Hypertension Diagnosis (20 pts) ---
    i10_found = result.get('i10_found', False)
    i10_active = result.get('i10_active', False)
    i10_code = result.get('i10_code', 'none')

    if i10_found and i10_active:
        score += 20
        subscores['hypertension_dx'] = 20
        feedback_parts.append(f"Hypertension diagnosis documented: ICD-10 {i10_code} (active)")
    elif i10_found:
        score += 10
        subscores['hypertension_dx'] = 10
        feedback_parts.append(f"Hypertension diagnosis {i10_code} found but not marked active")
    else:
        subscores['hypertension_dx'] = 0
        feedback_parts.append("MISSING: Essential hypertension (I10.x) diagnosis not found")

    # --- Criterion 3: G47 Sleep Apnea Diagnosis (20 pts) ---
    g47_found = result.get('g47_found', False)
    g47_active = result.get('g47_active', False)
    g47_code = result.get('g47_code', 'none')

    if g47_found and g47_active:
        score += 20
        subscores['sleep_apnea_dx'] = 20
        feedback_parts.append(f"Sleep apnea diagnosis documented: ICD-10 {g47_code} (active)")
    elif g47_found:
        score += 10
        subscores['sleep_apnea_dx'] = 10
        feedback_parts.append(f"Sleep apnea diagnosis {g47_code} found but not marked active")
    else:
        subscores['sleep_apnea_dx'] = 0
        feedback_parts.append("MISSING: Sleep apnea (G47.x) diagnosis not found")

    # --- Criterion 4: Antihypertensive Prescription (20 pts) ---
    presc_found = result.get('prescription_found', False)
    drug_name = result.get('drug_name', 'none')

    if presc_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Antihypertensive prescribed: {drug_name}")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: Appropriate antihypertensive prescription not found")

    # --- Criterion 5: Reassessment Appointment (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_date_str = result.get('appt_date', 'null')
    task_start_str = result.get('task_start_date', '')

    appt_score = 0
    if appt_found and appt_date_str != 'null':
        try:
            # Parse dates. appt_date_str might be 'YYYY-MM-DD HH:MM:SS'
            appt_date_only = appt_date_str.split(' ')[0]
            appt_dt = datetime.datetime.strptime(appt_date_only, '%Y-%m-%d').date()
            start_dt = datetime.datetime.strptime(task_start_str, '%Y-%m-%d').date()
            
            days_diff = (appt_dt - start_dt).days
            
            if 14 <= days_diff <= 30:
                appt_score = 20
                feedback_parts.append(f"Reassessment appointment scheduled correctly ({days_diff} days from today)")
            else:
                appt_score = 10
                feedback_parts.append(f"Appointment scheduled, but {days_diff} days from today (expected 14-30 days)")
        except Exception as e:
            logger.warning(f"Error parsing dates: {e}")
            appt_score = 5
            feedback_parts.append("Appointment scheduled, but could not parse the date correctly")
    else:
        feedback_parts.append("MISSING: No follow-up appointment scheduled")
    
    score += appt_score
    subscores['appointment'] = appt_score

    # Determine passing status
    passed = score >= 70 and subscores['clinical_eval'] >= 10 and (subscores['hypertension_dx'] > 0 or subscores['sleep_apnea_dx'] > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }