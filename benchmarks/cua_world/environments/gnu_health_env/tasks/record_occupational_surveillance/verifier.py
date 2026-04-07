#!/usr/bin/env python3
"""
Verifier for record_occupational_surveillance task.

Scoring breakdown (100 points total):
  - 20 pts: Occupational chemical exposure coding (Z57.x) for John Zenon
  - 20 pts: Surveillance health evaluation with acceptable vitals
  - 20 pts: Biological monitoring labs (>= 3 lab orders)
  - 20 pts: Lifestyle and risk factor documentation
  - 20 pts: Next annual surveillance appointment (335-395 days out)

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)


def verify_record_occupational_surveillance(traj, env_info, task_info):
    """Verify occupational health surveillance workflow for patient John Zenon."""
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
        copy_from_env('/tmp/record_occupational_surveillance_result.json', local_path)
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

    # --- Criterion 1: Z57.x Occupational Exposure Code (20 pts) ---
    z57_found = result.get('z57_found', False)
    z57_code = result.get('z57_code', 'none')
    z57_active = result.get('z57_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if z57_found and z57_active:
        score += 20
        subscores['exposure_coding'] = 20
        feedback_parts.append(f"Occupational exposure documented: ICD-10 {z57_code} (active)")
    elif z57_found:
        score += 15
        subscores['exposure_coding'] = 15
        feedback_parts.append(f"Z57.x exposure found ({z57_code}) but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['exposure_coding'] = 5
        feedback_parts.append(f"A diagnosis was added, but not an occupational exposure code (Z57.x)")
    else:
        subscores['exposure_coding'] = 0
        feedback_parts.append("MISSING: No occupational exposure code (Z57.x) found for John Zenon")

    # --- Criterion 2: Surveillance Evaluation (20 pts) ---
    eval_found = result.get('eval_found', False)
    systolic_str = result.get('eval_systolic', 'null')
    diastolic_str = result.get('eval_diastolic', 'null')
    hr_str = result.get('eval_hr', 'null')

    if eval_found:
        try:
            sys_val = float(systolic_str)
            dia_val = float(diastolic_str)
            hr_val = float(hr_hr_str) if 'hr_str' in locals() else float(hr_str)
            
            # Physiological checks
            if (90 <= sys_val <= 180) and (50 <= dia_val <= 120) and (50 <= hr_val <= 120):
                score += 20
                subscores['clinical_evaluation'] = 20
                feedback_parts.append(f"Surveillance evaluation documented with normal/acceptable vitals (BP {sys_val}/{dia_val}, HR {hr_val})")
            else:
                score += 14
                subscores['clinical_evaluation'] = 14
                feedback_parts.append(f"Surveillance evaluation found, but vitals are outside physiological range (BP {sys_val}/{dia_val}, HR {hr_val})")
        except (ValueError, TypeError):
            score += 10
            subscores['clinical_evaluation'] = 10
            feedback_parts.append("Surveillance evaluation found, but vital signs are missing or invalidly formatted")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical surveillance evaluation documented")

    # --- Criterion 3: Biological Monitoring Labs (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 3:
        score += 20
        subscores['monitoring_labs'] = 20
        feedback_parts.append(f"Biological monitoring panel complete: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 2:
        score += 14
        subscores['monitoring_labs'] = 14
        feedback_parts.append(f"Partial monitoring panel: 2 labs ordered ({new_lab_types}). Standard expects at least 3.")
    elif new_lab_count == 1:
        score += 7
        subscores['monitoring_labs'] = 7
        feedback_parts.append(f"Incomplete monitoring panel: 1 lab ordered ({new_lab_types})")
    else:
        subscores['monitoring_labs'] = 0
        feedback_parts.append("MISSING: No biological monitoring labs ordered")

    # --- Criterion 4: Lifestyle Documentation (20 pts) ---
    lifestyle_found = result.get('lifestyle_found', False)
    if lifestyle_found:
        score += 20
        subscores['lifestyle_doc'] = 20
        feedback_parts.append("Lifestyle and risk factor record created")
    else:
        subscores['lifestyle_doc'] = 0
        feedback_parts.append("MISSING: No lifestyle or risk factor record documented")

    # --- Criterion 5: Next Annual Surveillance Appt (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_date_str = result.get('appt_date', 'null')
    task_start_str = result.get('task_start_date', '')

    if appt_found and appt_date_str != 'null' and task_start_str:
        try:
            start_date = datetime.strptime(task_start_str, "%Y-%m-%d")
            appt_date = datetime.strptime(appt_date_str, "%Y-%m-%d")
            days_diff = (appt_date - start_date).days

            if 335 <= days_diff <= 395:
                score += 20
                subscores['annual_appointment'] = 20
                feedback_parts.append(f"Next annual surveillance appointment scheduled {days_diff} days out (correct timeframe)")
            elif 270 <= days_diff <= 450:
                score += 10
                subscores['annual_appointment'] = 10
                feedback_parts.append(f"Appointment scheduled {days_diff} days out — partial credit (expected roughly ~365 days)")
            else:
                score += 5
                subscores['annual_appointment'] = 5
                feedback_parts.append(f"Appointment scheduled {days_diff} days out — incorrect timeframe for ANNUAL surveillance")
        except ValueError:
            score += 5
            subscores['annual_appointment'] = 5
            feedback_parts.append("Appointment found, but date could not be parsed")
    elif appt_found:
        score += 5
        subscores['annual_appointment'] = 5
        feedback_parts.append("Appointment found, but date is missing")
    else:
        subscores['annual_appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Final Assessment ---
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }