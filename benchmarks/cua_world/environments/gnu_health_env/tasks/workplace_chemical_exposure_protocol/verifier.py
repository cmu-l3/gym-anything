#!/usr/bin/env python3
"""
Verifier for workplace_chemical_exposure_protocol task.

This is a very_hard task. The agent must independently document a workplace
chemical burn incident across multiple EHR modules.

Scoring breakdown (100 points total):
  - 20 pts: Chemical burn diagnosis (T-code or L-code) for Bonifacio Caput
  - 20 pts: Clinical evaluation documenting injury presentation
  - 20 pts: Wound care prescription (silver sulfadiazine/bacitracin/topical)
  - 20 pts: At least 2 toxicology/baseline lab orders
  - 20 pts: Wound reassessment follow-up within 3-10 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_workplace_chemical_exposure_protocol(traj, env_info, task_info):
    """Verify workplace chemical exposure protocol for patient Bonifacio Caput."""
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
        copy_from_env('/tmp/workplace_chemical_exposure_protocol_result.json', local_path)
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
    if 'bonifacio' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Bonifacio Caput, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Chemical burn diagnosis T-code (20 pts) ---
    t_found = result.get('t_code_found', False)
    t_code = result.get('t_code', 'none')
    t_active = result.get('t_code_active', False)
    t54_specific = result.get('t54_burn_specific', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if t_found and t_active and t54_specific:
        score += 20
        subscores['burn_diagnosis'] = 20
        feedback_parts.append(f"Chemical burn diagnosis documented: ICD-10 {t_code} (active, burn-specific)")
    elif t_found and t_active:
        score += 18
        subscores['burn_diagnosis'] = 18
        feedback_parts.append(f"T-code injury documented: {t_code} (active) — T54 would be more specific for chemical burns")
    elif t_found:
        score += 14
        subscores['burn_diagnosis'] = 14
        feedback_parts.append(f"T-code found ({t_code}) but not marked active")
    elif any_new_disease > 0:
        score += 7
        subscores['burn_diagnosis'] = 7
        feedback_parts.append("A diagnosis was added but not a T-code burn/injury classification")
    else:
        subscores['burn_diagnosis'] = 0
        feedback_parts.append("MISSING: No chemical burn diagnosis (T54.x or T20-T32) for Bonifacio Caput")

    # --- Criterion 2: Clinical evaluation (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_temp = result.get('evaluation_temperature', 'N/A')
    eval_hr = result.get('evaluation_heart_rate', 'N/A')

    if eval_found and eval_temp != 'null' and eval_hr != 'null':
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with vitals: temp={eval_temp}, HR={eval_hr}")
    elif eval_found:
        score += 14
        subscores['clinical_evaluation'] = 14
        feedback_parts.append("Clinical evaluation created but vital signs partially documented")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for chemical burn presentation")

    # --- Criterion 3: Wound care prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    wound_care_found = result.get('wound_care_found', False)
    wound_drug = result.get('wound_drug_name', 'none')

    if prescription_found and wound_care_found:
        score += 20
        subscores['wound_care_rx'] = 20
        feedback_parts.append(f"Wound care prescribed: {wound_drug}")
    elif prescription_found:
        score += 10
        subscores['wound_care_rx'] = 10
        feedback_parts.append("A prescription was created but could not confirm wound care medication (expected silver sulfadiazine/bacitracin)")
    else:
        subscores['wound_care_rx'] = 0
        feedback_parts.append("MISSING: No wound care prescription for Bonifacio Caput")

    # --- Criterion 4: Toxicology/baseline labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['toxicology_labs'] = 20
        feedback_parts.append(f"Toxicology/baseline workup: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['toxicology_labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — occupational exposure requires minimum 2 (tox screen + CBC/BMP)")
    else:
        subscores['toxicology_labs'] = 0
        feedback_parts.append("MISSING: No toxicology or baseline labs ordered")

    # --- Criterion 5: Wound reassessment 3-10 days (20 pts) ---
    appt_in_range = result.get('followup_appt_in_range', False)
    appt_date = result.get('followup_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    try:
        any_new_appts = int(any_new_appts)
    except (ValueError, TypeError):
        any_new_appts = 0

    if appt_in_range:
        score += 20
        subscores['wound_followup'] = 20
        feedback_parts.append(f"Wound reassessment scheduled for {appt_date} (within 3-10 day window)")
    elif any_new_appts > 0:
        score += 8
        subscores['wound_followup'] = 8
        feedback_parts.append("An appointment was scheduled but NOT in the 3-10 day wound reassessment window")
    else:
        subscores['wound_followup'] = 0
        feedback_parts.append("MISSING: No wound reassessment follow-up appointment")

    # --- Final result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "target_patient": target_name,
        "clinical_note": "Occupational chemical burn: T-code Dx + clinical eval + wound care Rx + tox/baseline labs + 3-10d wound follow-up"
    }
