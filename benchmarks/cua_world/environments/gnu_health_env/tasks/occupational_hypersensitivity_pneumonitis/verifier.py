#!/usr/bin/env python3
"""
Verifier for occupational_hypersensitivity_pneumonitis task.

This task requires the agent to diagnose and manage Sick Building Syndrome (Hypersensitivity Pneumonitis).
Scoring breakdown (100 points total):
  - 20 pts: Hypersensitivity Pneumonitis diagnosis (J67.x)
  - 20 pts: Clinical evaluation with Respiratory Rate >= 22 AND O2 Saturation <= 94%
  - 20 pts: Corticosteroid prescription (Prednisone, Methylprednisolone, etc.)
  - 20 pts: At least 2 diagnostic test orders (CXR, CBC, IgE, etc.)
  - 20 pts: Follow-up appointment within 14-28 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_hypersensitivity_pneumonitis(traj, env_info, task_info):
    """Verify management protocol for Hypersensitivity Pneumonitis (John Zenon)."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_hypersensitivity_pneumonitis_result.json', local_path)
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

    # CRITICAL CHECK: Correct patient target
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

    # --- Criterion 1: J67 Hypersensitivity Pneumonitis Diagnosis (20 pts) ---
    j67_found = result.get('j67_found', False)
    j67_active = result.get('j67_active', False)
    j67_code = result.get('j67_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except:
        any_new_disease = 0

    if j67_found and j67_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Hypersensitivity pneumonitis diagnosis documented: ICD-10 {j67_code} (active)")
    elif j67_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"J67 HP found but NOT marked active (code: {j67_code})")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an environmental J67.x code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No Hypersensitivity Pneumonitis diagnosis (J67.x) found for John Zenon")

    # --- Criterion 2: Clinical evaluation with Respiratory Distress (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_rr_str = result.get('evaluation_rr', 'null')
    eval_o2_str = result.get('evaluation_o2', 'null')

    has_tachypnea = False
    has_hypoxia = False
    eval_rr = 0
    eval_o2 = 100

    if eval_found:
        try:
            eval_rr = float(eval_rr_str)
            if eval_rr >= 22:
                has_tachypnea = True
        except:
            pass

        try:
            eval_o2 = float(eval_o2_str)
            if eval_o2 <= 94:
                has_hypoxia = True
        except:
            pass

    if eval_found and has_tachypnea and has_hypoxia:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append(f"Evaluation documented respiratory distress: RR={eval_rr}, O2={eval_o2}%")
    elif eval_found and (has_tachypnea or has_hypoxia):
        score += 12
        subscores['evaluation'] = 12
        feedback_parts.append(f"Evaluation partial vitals: RR={eval_rr_str} (tachy={has_tachypnea}), O2={eval_o2_str}% (hypox={has_hypoxia})")
    elif eval_found:
        score += 5
        subscores['evaluation'] = 5
        feedback_parts.append(f"Evaluation created but vitals missing or normal (need RR>=22, O2<=94). Found: RR={eval_rr_str}, O2={eval_o2_str}")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for respiratory distress")

    # --- Criterion 3: Corticosteroid prescription (20 pts) ---
    presc_found = result.get('prescription_found', False)
    steroid_found = result.get('steroid_found', False)
    steroid_name = result.get('steroid_name', 'none')

    if presc_found and steroid_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Corticosteroid prescribed: {steroid_name}")
    elif presc_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but no corticosteroid (e.g., Prednisone, Fluticasone) found")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No corticosteroid prescription created")

    # --- Criterion 4: Diagnostic orders >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except:
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['diagnostics'] = 20
        feedback_parts.append(f"Sufficient diagnostic orders: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['diagnostics'] = 10
        feedback_parts.append(f"Only 1 diagnostic order created ({new_lab_types}) — expected at least 2")
    else:
        subscores['diagnostics'] = 0
        feedback_parts.append("MISSING: No new diagnostic/lab tests ordered")

    # --- Criterion 5: Follow-up Appointment 14-28 days (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_date = result.get('appointment_date', 'none')
    appt_days = result.get('appointment_days_delta', 0)
    try:
        appt_days = int(appt_days)
    except:
        appt_days = 0

    if appt_found and 14 <= appt_days <= 28:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Follow-up scheduled correctly in {appt_days} days (date: {appt_date})")
    elif appt_found and appt_days > 0:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up scheduled in {appt_days} days (expected 14-28 days)")
    elif appt_found:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append("Appointment scheduled but date is invalid or in the past")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }