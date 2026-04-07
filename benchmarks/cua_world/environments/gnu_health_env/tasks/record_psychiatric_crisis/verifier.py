#!/usr/bin/env python3
"""
Verifier for record_psychiatric_crisis task.

This is a very_hard task evaluating the agent's ability to document and manage
an acute psychiatric emergency in the occupational health setting.

Scoring breakdown (100 points total):
  - 20 pts: Psychotic disorder diagnosis (ICD-10 F20-F29) for Bonifacio Caput
  - 20 pts: Clinical evaluation documenting elevated HR (>=90) indicating agitation
  - 20 pts: Antipsychotic medication prescribed
  - 20 pts: At least 2 baseline lab orders for psychotropic monitoring
  - 20 pts: Psychiatric crisis follow-up appointment within 5-14 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_record_psychiatric_crisis(traj, env_info, task_info):
    """Verify psychiatric crisis evaluation and management for patient Bonifacio Caput."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_psychiatric_crisis_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Bonifacio Caput not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'bonifacio' not in target_name.lower() or 'caput' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Bonifacio Caput, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Psychiatric F-code diagnosis (20 pts) ---
    f_found = result.get('f_code_found', False)
    f_active = result.get('f_code_active', False)
    f_code = result.get('f_code', 'none')
    f23_specific = result.get('f23_specific', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if f_found and f_active and f23_specific:
        score += 20
        subscores['psychiatric_diagnosis'] = 20
        feedback_parts.append(f"Acute psychotic disorder documented correctly: ICD-10 {f_code} (active)")
    elif f_found and f_active:
        score += 18
        subscores['psychiatric_diagnosis'] = 18
        feedback_parts.append(f"Psychotic disorder documented: ICD-10 {f_code} (active) — F23 preferred for acute crisis")
    elif f_found:
        score += 12
        subscores['psychiatric_diagnosis'] = 12
        feedback_parts.append(f"F-code diagnosis {f_code} found but NOT marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['psychiatric_diagnosis'] = 5
        feedback_parts.append(f"A diagnosis was added but not an F20-F29 psychotic disorder classification")
    else:
        subscores['psychiatric_diagnosis'] = 0
        feedback_parts.append("MISSING: No psychiatric diagnosis (F-code) documented for Bonifacio Caput")

    # --- Criterion 2: Clinical evaluation with elevated heart rate (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_temp = result.get('evaluation_temperature', 'N/A')
    eval_hr = result.get('evaluation_heart_rate', 'N/A')
    eval_has_tachy = result.get('evaluation_has_tachycardia', False)

    if eval_found and eval_has_tachy and eval_temp != 'null':
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with vitals: HR={eval_hr} bpm (agitation), Temp={eval_temp}")
    elif eval_found and eval_has_tachy:
        score += 16
        subscores['clinical_evaluation'] = 16
        feedback_parts.append(f"Clinical evaluation documented with elevated HR={eval_hr} bpm, but missing temperature")
    elif eval_found and eval_hr != 'null':
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append(f"Clinical evaluation created but heart rate not elevated enough to reflect agitation (HR={eval_hr})")
    elif eval_found:
        score += 5
        subscores['clinical_evaluation'] = 5
        feedback_parts.append("Clinical evaluation created but vital signs completely missing")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for the psychiatric presentation")

    # --- Criterion 3: Antipsychotic prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    ap_found = result.get('antipsychotic_found', False)
    ap_name = result.get('antipsychotic_name', 'none')

    if prescription_found and ap_found:
        score += 20
        subscores['antipsychotic_prescription'] = 20
        feedback_parts.append(f"Antipsychotic medication prescribed: {ap_name}")
    elif prescription_found:
        score += 5
        subscores['antipsychotic_prescription'] = 5
        feedback_parts.append(f"A prescription was created but it did not contain a recognized antipsychotic")
    else:
        subscores['antipsychotic_prescription'] = 0
        feedback_parts.append("MISSING: No antipsychotic medication prescribed")

    # --- Criterion 4: Baseline labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['baseline_labs'] = 20
        feedback_parts.append(f"Baseline monitoring labs ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['baseline_labs'] = 10
        feedback_parts.append(f"Only 1 baseline lab ordered ({new_lab_types}) — standard protocol requires at least 2")
    else:
        subscores['baseline_labs'] = 0
        feedback_parts.append("MISSING: No baseline laboratory orders placed for psychotropic monitoring")

    # --- Criterion 5: Crisis follow-up appointment 5-14 days (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days_diff = result.get('appointment_days_diff', -999)
    
    try:
        appt_days_diff = int(appt_days_diff)
    except (ValueError, TypeError):
        appt_days_diff = -999

    if appt_found and 5 <= appt_days_diff <= 14:
        score += 20
        subscores['crisis_followup'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled appropriately in {appt_days_diff} days")
    elif appt_found and appt_days_diff > 14:
        score += 12
        subscores['crisis_followup'] = 12
        feedback_parts.append(f"Follow-up scheduled too late ({appt_days_diff} days) — acute crisis requires 5-14 day reassessment")
    elif appt_found and appt_days_diff >= 0:
        score += 12
        subscores['crisis_followup'] = 12
        feedback_parts.append(f"Follow-up scheduled too soon ({appt_days_diff} days) — standard window is 5-14 days")
    elif appt_found:
        score += 0
        subscores['crisis_followup'] = 0
        feedback_parts.append(f"Appointment scheduled in the past ({appt_days_diff} days)")
    else:
        subscores['crisis_followup'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Determine pass/fail ---
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }