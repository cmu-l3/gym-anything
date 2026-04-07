#!/usr/bin/env python3
"""
Verifier for occupational_cytotoxic_exposure task.

This task requires the agent to document an occupational hazard exposure incident.

Scoring breakdown (100 points total):
  - 20 pts: Toxic exposure diagnosis (T45.x or T65.x) for Ana Isabel Betz
  - 15 pts: Clinical evaluation documenting baseline HR
  - 25 pts: At least 3 toxicity monitoring lab orders
  - 20 pts: Sterile irrigation prescription (Sodium Chloride/Saline)
  - 20 pts: Medical surveillance follow-up appointment within 3-7 days

Pass threshold: score >= 75
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_cytotoxic_exposure(traj, env_info, task_info):
    """Verify cytotoxic exposure protocol for patient Ana Isabel Betz."""
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
        copy_from_env('/tmp/occupational_cytotoxic_exposure_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Ana Isabel Betz not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'ana' not in target_name.lower() or 'betz' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Ana Betz, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Toxic exposure diagnosis (20 pts) ---
    t_found = result.get('t_code_found', False)
    t_code = result.get('t_code', 'none')
    t_active = result.get('t_code_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if t_found and t_active:
        score += 20
        subscores['exposure_diagnosis'] = 20
        feedback_parts.append(f"Toxic exposure diagnosis documented: ICD-10 {t_code} (active)")
    elif t_found:
        score += 15
        subscores['exposure_diagnosis'] = 15
        feedback_parts.append(f"T-code exposure found ({t_code}) but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['exposure_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a toxic/antineoplastic T-code (T45/T65)")
    else:
        subscores['exposure_diagnosis'] = 0
        feedback_parts.append("MISSING: No toxic exposure diagnosis (T45.x or T65.x) for Ana Isabel Betz")

    # --- Criterion 2: Clinical evaluation with HR (15 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_hr = result.get('evaluation_heart_rate', 'null')

    if eval_found and eval_hr != 'null':
        score += 15
        subscores['clinical_evaluation'] = 15
        feedback_parts.append(f"Clinical evaluation documented with baseline HR: {eval_hr}")
    elif eval_found:
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append("Clinical evaluation created but heart rate not documented")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for the exposure incident")

    # --- Criterion 3: Toxicity labs >= 3 (25 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 3:
        score += 25
        subscores['toxicity_labs'] = 25
        feedback_parts.append(f"Toxicity panel complete: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 2:
        score += 15
        subscores['toxicity_labs'] = 15
        feedback_parts.append(f"Partial toxicity panel: only 2 labs ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 8
        subscores['toxicity_labs'] = 8
        feedback_parts.append(f"Insufficient toxicity panel: only 1 lab ordered ({new_lab_types})")
    else:
        subscores['toxicity_labs'] = 0
        feedback_parts.append("MISSING: No toxicity monitoring labs ordered")

    # --- Criterion 4: Irrigation prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    irrigation_found = result.get('irrigation_found', False)
    irrigation_drug = result.get('irrigation_drug_name', 'none')

    if prescription_found and irrigation_found:
        score += 20
        subscores['irrigation_rx'] = 20
        feedback_parts.append(f"Irrigation solution prescribed: {irrigation_drug}")
    elif prescription_found:
        score += 5
        subscores['irrigation_rx'] = 5
        feedback_parts.append("A prescription was added but it did not match Sodium Chloride / Saline")
    else:
        subscores['irrigation_rx'] = 0
        feedback_parts.append("MISSING: No sterile irrigation prescription created")

    # --- Criterion 5: Follow-up appointment in 3-7 days (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days_raw = result.get('appointment_days_from_start', 'null')
    
    try:
        appt_days = int(appt_days_raw) if appt_days_raw != 'null' else -1
    except (ValueError, TypeError):
        appt_days = -1

    if appt_found and 3 <= appt_days <= 7:
        score += 20
        subscores['followup_appt'] = 20
        feedback_parts.append(f"Surveillance follow-up correctly scheduled in {appt_days} days")
    elif appt_found and appt_days != -1:
        score += 10
        subscores['followup_appt'] = 10
        feedback_parts.append(f"Follow-up scheduled in {appt_days} days — expected 3-7 days for toxic exposure surveillance")
    elif appt_found:
        score += 5
        subscores['followup_appt'] = 5
        feedback_parts.append("Appointment found but date could not be parsed")
    else:
        subscores['followup_appt'] = 0
        feedback_parts.append("MISSING: No medical surveillance follow-up appointment scheduled")

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }