#!/usr/bin/env python3
"""
Verifier for occupational_heat_exhaustion_management task.

Evaluates an occupational heat illness management workflow across 5 criteria:
  - 20 pts: Clinical Evaluation with abnormal vitals (Temp>=38.5, HR>=110, Sys<=100)
  - 20 pts: Heat illness diagnosis (T67.x)
  - 20 pts: Hydration therapy prescription (Sodium chloride / Ringer's)
  - 20 pts: At least 2 metabolic laboratory orders
  - 20 pts: Follow-up appointment scheduled within 2 to 7 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_heat_exhaustion_management(traj, env_info, task_info):
    """Verify occupational heat exhaustion management for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_heat_exhaustion_result.json', local_path)
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
            "feedback": "CRITICAL: Target patient John Zenon not found — setup may have failed.",
            "subscores": {}
        }

    # --- Criterion 1: Clinical Evaluation (20 pts) ---
    eval_found = result.get('eval_found', False)
    
    # Safely cast evaluation metrics to float
    def safe_float(val):
        try:
            return float(val)
        except (ValueError, TypeError):
            return 0.0

    eval_temp = safe_float(result.get('eval_temp', 0))
    eval_hr = safe_float(result.get('eval_hr', 0))
    eval_sys = safe_float(result.get('eval_sys', 0))

    if eval_found:
        vitals_score = 0
        vitals_fb = []
        
        if eval_temp >= 38.5:
            vitals_score += 7
            vitals_fb.append(f"Temp {eval_temp} (>=38.5)")
        else:
            vitals_fb.append(f"Temp {eval_temp} (<38.5)")

        if eval_hr >= 110:
            vitals_score += 7
            vitals_fb.append(f"HR {eval_hr} (>=110)")
        else:
            vitals_fb.append(f"HR {eval_hr} (<110)")

        if 0 < eval_sys <= 100:
            vitals_score += 6
            vitals_fb.append(f"SysBP {eval_sys} (<=100)")
        elif eval_sys > 100:
            vitals_fb.append(f"SysBP {eval_sys} (>100)")
        else:
            vitals_fb.append("SysBP missing/invalid")

        score += vitals_score
        subscores['evaluation'] = vitals_score
        if vitals_score == 20:
            feedback_parts.append(f"Evaluation documented with all required abnormal vitals ({', '.join(vitals_fb)})")
        else:
            feedback_parts.append(f"Evaluation documented, partial vitals match: {', '.join(vitals_fb)}")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 2: Heat exhaustion diagnosis T67.x (20 pts) ---
    t67_found = result.get('t67_found', False)
    t67_active = result.get('t67_active', False)
    t67_code = result.get('t67_code', 'none')
    any_new_disease = int(result.get('any_new_disease_count', 0))

    if t67_found and t67_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Heat illness diagnosis documented: ICD-10 {t67_code} (active)")
    elif t67_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"T67 heat illness found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A new diagnosis was added, but not a T67 heat illness code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No heat illness diagnosis (T67) documented")

    # --- Criterion 3: Hydration therapy prescription (20 pts) ---
    presc_found = result.get('prescription_found', False)
    hyd_found = result.get('hydration_found', False)
    hyd_drug = result.get('hydration_drug_name', 'none')

    if presc_found and hyd_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"IV Hydration prescribed: {hyd_drug}")
    elif presc_found:
        score += 8
        subscores['prescription'] = 8
        feedback_parts.append("Prescription created, but no matching hydration fluid found (expected Saline/Sodium Chloride/Ringer's)")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No medications/fluids prescribed")

    # --- Criterion 4: Metabolic Lab Orders (20 pts) ---
    lab_count = int(result.get('new_lab_count', 0))
    lab_types = result.get('new_lab_types', '')

    if lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Sufficient lab tests ordered ({lab_count} found: {lab_types})")
    elif lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Only 1 lab test ordered ({lab_types}) - requested at least 2")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No lab tests ordered")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_days_diff = int(result.get('appt_days_diff', -999))

    if appt_found:
        if 2 <= appt_days_diff <= 7:
            score += 20
            subscores['appointment'] = 20
            feedback_parts.append(f"Follow-up appointment scheduled appropriately ({appt_days_diff} days from now)")
        else:
            score += 10
            subscores['appointment'] = 10
            feedback_parts.append(f"Appointment scheduled, but outside target range ({appt_days_diff} days, requested 2-7 days)")
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