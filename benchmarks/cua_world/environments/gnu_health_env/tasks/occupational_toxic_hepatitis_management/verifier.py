#!/usr/bin/env python3
"""
Verifier for occupational_toxic_hepatitis_management task.

This is a very_hard task. The agent must independently manage a multi-module
toxicological workflow in GNU Health.

Scoring breakdown (100 points total):
  - 20 pts: Toxic liver disease diagnosis (K71.x) for John Zenon
  - 20 pts: Adverse chemical reaction logged in allergy profile for solvents
  - 20 pts: At least 3 hepatic monitoring labs ordered
  - 20 pts: Antiemetic prescription (e.g., Ondansetron)
  - 20 pts: Follow-up appointment within 3-7 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_toxic_hepatitis_management(traj, env_info, task_info):
    """Verify occupational toxic hepatitis protocol for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_toxic_hepatitis_management_result.json', local_path)
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

    # --- Criterion 1: Toxic Liver Disease diagnosis K71 (20 pts) ---
    k71_found = result.get('k71_found', False)
    k71_active = result.get('k71_active', False)
    k71_code = result.get('k71_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    
    if k71_found and k71_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Toxic liver disease diagnosis documented: ICD-10 {k71_code} (active)")
    elif k71_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"K71 diagnosis {k71_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a K71 code for toxic liver disease")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No toxic liver disease diagnosis (K71) for John Zenon")

    # --- Criterion 2: Solvent Adverse Reaction (20 pts) ---
    allergy_found = result.get('solvent_allergy_found', False)
    allergy_name = result.get('solvent_allergy_name', 'none')
    any_new_allergy = result.get('any_new_allergy_count', 0)
    
    if allergy_found:
        score += 20
        subscores['adverse_reaction'] = 20
        feedback_parts.append(f"Adverse chemical reaction logged: {allergy_name}")
    elif any_new_allergy > 0:
        score += 8
        subscores['adverse_reaction'] = 8
        feedback_parts.append("An allergy/reaction was recorded but did not reference the specific solvents (toluene, carbon tetrachloride)")
    else:
        subscores['adverse_reaction'] = 0
        feedback_parts.append("MISSING: No adverse chemical reaction documented")

    # --- Criterion 3: Hepatic Labs >= 3 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 3:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Hepatic monitoring panel ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 2:
        score += 13
        subscores['labs'] = 13
        feedback_parts.append(f"Only 2 labs ordered ({new_lab_types}) — hepatic monitoring typically requires broader screening")
    elif new_lab_count == 1:
        score += 7
        subscores['labs'] = 7
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — insufficient for hepatic function monitoring")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No hepatic lab tests ordered")

    # --- Criterion 4: Antiemetic Prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    antiemetic_found = result.get('antiemetic_found', False)
    antiemetic_name = result.get('antiemetic_name', 'none')

    if antiemetic_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Antiemetic prescribed: {antiemetic_name}")
    elif prescription_found:
        score += 8
        subscores['prescription'] = 8
        feedback_parts.append("A prescription was made but not identified as an antiemetic (e.g., Ondansetron)")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No antiemetic prescribed for nausea")

    # --- Criterion 5: Follow-up 3-7 days (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_days_diff = result.get('appt_days_diff', 0)
    try:
        appt_days_diff = int(appt_days_diff)
    except (ValueError, TypeError):
        appt_days_diff = 0

    if appt_found and 3 <= appt_days_diff <= 7:
        score += 20
        subscores['follow_up'] = 20
        feedback_parts.append(f"Follow-up scheduled correctly ({appt_days_diff} days from today)")
    elif appt_found and appt_days_diff > 7:
        score += 15
        subscores['follow_up'] = 15
        feedback_parts.append(f"Follow-up scheduled ({appt_days_diff} days) but later than recommended 3-7 days for acute toxicity")
    elif appt_found and appt_days_diff >= 0:
        score += 10
        subscores['follow_up'] = 10
        feedback_parts.append(f"Follow-up scheduled ({appt_days_diff} days) but earlier than recommended window")
    elif appt_found:
        score += 5
        subscores['follow_up'] = 5
        feedback_parts.append("Follow-up appointment found but date is invalid (in the past)")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Final Assessment ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores
    }