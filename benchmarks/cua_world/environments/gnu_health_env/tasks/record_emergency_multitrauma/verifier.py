#!/usr/bin/env python3
"""
Verifier for record_emergency_multitrauma task.

This is a very_hard task. The agent must independently manage a multi-trauma
assessment requiring multiple clinical entries across various GNU Health modules.

Scoring breakdown (100 points total):
  - 20 pts: Multiple trauma diagnoses (at least 3 ICD-10 S-codes)
  - 20 pts: Trauma clinical evaluation (HR >= 110 AND SBP <= 100)
  - 20 pts: Trauma laboratory panel (at least 3 lab orders)
  - 20 pts: Acute analgesia prescription (Morphine/Ketorolac/Tramadol/etc.)
  - 20 pts: Orthopedic follow-up appointment within 5-14 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_record_emergency_multitrauma(traj, env_info, task_info):
    """Verify emergency multi-trauma assessment for patient Matt Zenon Betz."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_emergency_multitrauma_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Matt Zenon Betz not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'matt' not in target_name.lower() or 'betz' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Matt Betz, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Multiple S-code diagnoses (20 pts) ---
    s_code_count = result.get('s_code_count', 0)
    s_codes_found = result.get('s_codes_found', '')
    any_new_disease = result.get('any_new_disease_count', 0)
    
    try:
        s_code_count = int(s_code_count)
    except (ValueError, TypeError):
        s_code_count = 0

    if s_code_count >= 3:
        score += 20
        subscores['trauma_diagnoses'] = 20
        feedback_parts.append(f"Multiple trauma diagnoses documented: 3+ S-codes found ({s_codes_found})")
    elif s_code_count in [1, 2]:
        score += 10
        subscores['trauma_diagnoses'] = 10
        feedback_parts.append(f"Partial trauma diagnoses documented: {s_code_count}/3 required S-codes found ({s_codes_found})")
    elif any_new_disease > 0:
        score += 5
        subscores['trauma_diagnoses'] = 5
        feedback_parts.append(f"Diagnosis added but no S-codes recorded. A multi-trauma fall requires S-codes for injury classification.")
    else:
        subscores['trauma_diagnoses'] = 0
        feedback_parts.append("MISSING: No trauma injury diagnoses (S-codes) documented")

    # --- Criterion 2: Clinical Evaluation (HR >= 110, SBP <= 100) (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_hr_str = result.get('evaluation_hr', 'null')
    eval_sbp_str = result.get('evaluation_sbp', 'null')
    
    eval_hr = 0
    eval_sbp = 999
    try:
        if eval_hr_str != 'null':
            eval_hr = float(eval_hr_str)
        if eval_sbp_str != 'null':
            eval_sbp = float(eval_sbp_str)
    except ValueError:
        pass

    if eval_found:
        hr_valid = eval_hr >= 110
        sbp_valid = eval_sbp <= 100 and eval_sbp > 0
        
        if hr_valid and sbp_valid:
            score += 20
            subscores['clinical_evaluation'] = 20
            feedback_parts.append(f"Hemodynamic shock evaluation documented (HR: {eval_hr}, SBP: {eval_sbp})")
        elif hr_valid or sbp_valid:
            score += 10
            subscores['clinical_evaluation'] = 10
            feedback_parts.append(f"Evaluation partially documented vital signs (HR: {eval_hr_str}, SBP: {eval_sbp_str} - Expected HR>=110, SBP<=100)")
        else:
            score += 5
            subscores['clinical_evaluation'] = 5
            feedback_parts.append(f"Evaluation recorded but vital signs incorrect (HR: {eval_hr_str}, SBP: {eval_sbp_str})")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation with vital signs documented")

    # --- Criterion 3: Trauma Lab Panel (>= 3 orders) (20 pts) ---
    lab_count = result.get('new_lab_count', 0)
    lab_types = result.get('new_lab_types', '')
    try:
        lab_count = int(lab_count)
    except (ValueError, TypeError):
        lab_count = 0

    if lab_count >= 3:
        score += 20
        subscores['trauma_labs'] = 20
        feedback_parts.append(f"Comprehensive trauma lab panel ordered: {lab_count} labs ({lab_types})")
    elif lab_count in [1, 2]:
        score += 10
        subscores['trauma_labs'] = 10
        feedback_parts.append(f"Partial lab panel ordered: {lab_count} labs ({lab_types}) - Expected at least 3")
    else:
        subscores['trauma_labs'] = 0
        feedback_parts.append("MISSING: No trauma lab workup ordered")

    # --- Criterion 4: Acute Analgesia Prescription (20 pts) ---
    presc_found = result.get('prescription_found', False)
    analgesic_found = result.get('analgesic_found', False)
    analgesic_name = result.get('analgesic_name', 'none')

    if presc_found and analgesic_found:
        score += 20
        subscores['acute_analgesia'] = 20
        feedback_parts.append(f"Acute analgesia prescribed: {analgesic_name}")
    elif presc_found:
        score += 5
        subscores['acute_analgesia'] = 5
        feedback_parts.append("A prescription was made but no recognized acute trauma analgesic found")
    else:
        subscores['acute_analgesia'] = 0
        feedback_parts.append("MISSING: No acute analgesia prescribed for trauma pain management")

    # --- Criterion 5: Orthopedic Follow-up (5-14 days) (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days_str = result.get('appointment_days_diff', 'null')
    
    appt_days = -999
    try:
        if appt_days_str != 'null':
            appt_days = int(appt_days_str)
    except ValueError:
        pass

    if appt_found:
        if 5 <= appt_days <= 14:
            score += 20
            subscores['orthopedic_followup'] = 20
            feedback_parts.append(f"Orthopedic follow-up correctly scheduled {appt_days} days out (within 5-14 day window)")
        else:
            score += 8
            subscores['orthopedic_followup'] = 8
            feedback_parts.append(f"Follow-up scheduled but outside recommended window: {appt_days} days out (Expected 5-14 days)")
    else:
        subscores['orthopedic_followup'] = 0
        feedback_parts.append("MISSING: No orthopedic follow-up appointment scheduled")

    # Overall pass logic
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "subscores": subscores
    }