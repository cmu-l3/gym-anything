#!/usr/bin/env python3
"""
Verifier for occupational_ergonomic_rsi_management task.

This task requires the agent to navigate 5 different modules:
1. Diagnosis: Carpal Tunnel (G56.x)
2. Evaluation: Heart Rate (60-100)
3. Prescription: Analgesic/NSAID
4. Laboratory: >= 1 diagnostic order
5. Appointment: 14 to 30 days follow-up

Score Breakdown (100 pts total, 20 pts per criterion). Pass threshold: 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_ergonomic_rsi_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_ergonomic_rsi_management_result.json', local_path)
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

    # Criterion 1: G56.x Diagnosis (20 pts)
    g56_found = result.get('g56_found', False)
    g56_active = result.get('g56_active', False)
    g56_code = result.get('g56_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    
    if g56_found and g56_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Carpal Tunnel diagnosis documented: ICD-10 {g56_code} (active)")
    elif g56_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Carpal Tunnel diagnosis {g56_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a Carpal Tunnel (G56.x) code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No Carpal Tunnel diagnosis for John Zenon")

    # Criterion 2: Clinical Evaluation (20 pts)
    eval_found = result.get('evaluation_found', False)
    eval_hr = result.get('evaluation_heart_rate', 'N/A')
    eval_hr_valid = result.get('evaluation_hr_valid', False)
    
    if eval_found and eval_hr_valid:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with resting HR: {eval_hr} bpm")
    elif eval_found:
        score += 10
        subscores['evaluation'] = 10
        feedback_parts.append(f"Clinical evaluation documented but HR ({eval_hr}) is invalid or missing (expected 60-100)")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 3: NSAID / Analgesic Prescription (20 pts)
    presc_found = result.get('prescription_found', False)
    analgesic_found = result.get('analgesic_found', False)
    analgesic_name = result.get('analgesic_name', 'none')

    if presc_found and analgesic_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Analgesic/NSAID prescribed: {analgesic_name}")
    elif presc_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but no target analgesic/NSAID identified")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No analgesic medication prescribed")

    # Criterion 4: Diagnostic Lab Order (20 pts)
    new_lab_count = result.get('new_lab_count', 0)
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 1:
        score += 20
        subscores['diagnostic_order'] = 20
        feedback_parts.append(f"Diagnostic test ordered ({new_lab_count} orders found)")
    else:
        subscores['diagnostic_order'] = 0
        feedback_parts.append("MISSING: No diagnostic or baseline laboratory tests ordered")

    # Criterion 5: Follow-up Appointment (20 pts)
    appt_found = result.get('appointment_found', False)
    appt_diff = result.get('appointment_diff_days', 'null')

    if appt_found:
        try:
            diff_days = int(appt_diff)
            if 14 <= diff_days <= 30:
                score += 20
                subscores['appointment'] = 20
                feedback_parts.append(f"Follow-up scheduled correctly ({diff_days} days from today)")
            else:
                score += 10
                subscores['appointment'] = 10
                feedback_parts.append(f"Follow-up scheduled but outside the 14-30 day window ({diff_days} days)")
        except (ValueError, TypeError):
            score += 5
            subscores['appointment'] = 5
            feedback_parts.append("Appointment found but date couldn't be evaluated")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # Evaluate final passing state
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }