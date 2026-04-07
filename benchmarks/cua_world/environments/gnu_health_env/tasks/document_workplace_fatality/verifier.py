#!/usr/bin/env python3
"""
Verifier for document_workplace_fatality task.

Scoring breakdown (100 points total):
  - 20 pts: Patient marked as deceased with date of death set to today
  - 20 pts: Cause of death (COD) set to T59.x code
  - 20 pts: Active disease record created for toxic gas exposure (T59.x)
  - 20 pts: Contributing disease record created for respiratory failure (J96/J68/J80)
  - 20 pts: Final clinical evaluation documented

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_document_workplace_fatality(traj, env_info, task_info):
    """Verify workplace fatality documentation for patient Bonifacio Caput."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/document_workplace_fatality_result.json', local_path)
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

    # CRITICAL CHECK: Ensure task ran against the correct patient
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient Bonifacio Caput not found — setup may have failed.",
            "subscores": {}
        }

    # Criterion 1: Deceased Status + Date of Death (20 pts)
    deceased = str(result.get('patient_deceased', 'false')).lower()
    dod = result.get('patient_dod', 'null')
    today_date = result.get('today_date', '1970-01-01')

    if deceased in ['t', 'true', '1']:
        if today_date in dod:
            score += 20
            subscores['deceased_status'] = 20
            feedback_parts.append(f"Patient correctly marked deceased with DOD: {dod}")
        elif dod != 'null':
            score += 15
            subscores['deceased_status'] = 15
            feedback_parts.append(f"Patient marked deceased, but DOD ({dod}) does not match expected ({today_date})")
        else:
            score += 10
            subscores['deceased_status'] = 10
            feedback_parts.append("Patient marked deceased, but no Date of Death recorded")
    else:
        subscores['deceased_status'] = 0
        feedback_parts.append("MISSING: Patient was not marked as deceased")

    # Criterion 2: Cause of Death (COD) ICD-10 code (20 pts)
    cod = result.get('patient_cod', 'null')
    if cod != 'null' and cod.startswith('T59'):
        score += 20
        subscores['cause_of_death'] = 20
        feedback_parts.append(f"Cause of Death recorded correctly: {cod}")
    elif cod != 'null':
        score += 5
        subscores['cause_of_death'] = 5
        feedback_parts.append(f"Cause of Death recorded as {cod}, but expected a T59.x toxic gas exposure code")
    else:
        subscores['cause_of_death'] = 0
        feedback_parts.append("MISSING: No Cause of Death (COD) recorded in the patient demographic profile")

    # Criterion 3: Toxic Exposure Disease Record (20 pts)
    t59_found = result.get('t59_disease_found', False)
    t59_active = str(result.get('t59_disease_active', 'false')).lower()
    t59_code = result.get('t59_disease_code', 'null')

    if t59_found:
        if t59_active in ['t', 'true', '1']:
            score += 20
            subscores['toxic_disease_record'] = 20
            feedback_parts.append(f"Active disease record created for toxic gas exposure ({t59_code})")
        else:
            score += 15
            subscores['toxic_disease_record'] = 15
            feedback_parts.append(f"Disease record created for {t59_code}, but it was not marked active")
    else:
        subscores['toxic_disease_record'] = 0
        feedback_parts.append("MISSING: No disease record created for T59.x toxic exposure")

    # Criterion 4: Contributing Respiratory Cause (20 pts)
    j_found = result.get('j_disease_found', False)
    j_code = result.get('j_disease_code', 'null')

    if j_found:
        score += 20
        subscores['contributing_disease'] = 20
        feedback_parts.append(f"Contributing disease record created for terminal respiratory condition ({j_code})")
    else:
        subscores['contributing_disease'] = 0
        feedback_parts.append("MISSING: No contributing disease record (J96, J68, or J80) created for acute respiratory failure")

    # Criterion 5: Final Clinical Evaluation (20 pts)
    eval_count = result.get('new_eval_count', 0)
    try:
        eval_count = int(eval_count)
    except (ValueError, TypeError):
        eval_count = 0

    if eval_count > 0:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append("Final clinical evaluation recorded successfully")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No new clinical evaluation was documented")

    # Final verdict
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }