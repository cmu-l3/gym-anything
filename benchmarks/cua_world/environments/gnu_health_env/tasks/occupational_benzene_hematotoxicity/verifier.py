#!/usr/bin/env python3
"""
Verifier for occupational_benzene_hematotoxicity task.

The agent must complete a regulatory medical surveillance protocol.
Scoring breakdown (100 points total):
  - 20 pts: Target Diagnosis (T52.x or D61.x) active for John Zenon
  - 20 pts: Clinical evaluation entry
  - 20 pts: At least 3 hematology lab test orders
  - 20 pts: Supportive vitamin/hematinic prescription
  - 20 pts: Follow-up appointment within 7-14 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_benzene_hematotoxicity(traj, env_info, task_info):
    """Verify occupational benzene hematotoxicity protocol completion."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Copy result JSON from VM ---
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_benzene_hematotoxicity_result.json', local_path)
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

    # --- Verify Patient Integrity ---
    target_id = result.get('target_patient_id', 0)
    target_name = result.get('target_patient_name', '')
    if not target_id or 'john' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target or not found. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }
        
    # --- Criterion 1: Diagnosis (20 pts) ---
    diag_found = result.get('diag_found', False)
    diag_active = result.get('diag_active', False)
    diag_code = result.get('diag_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    
    if diag_found and diag_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Benzene toxicity or aplastic anemia diagnosis documented: ICD-10 {diag_code} (active)")
    elif diag_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Diagnosis {diag_code} found but not marked active")
    elif any_new_disease > 0:
        score += 8
        subscores['diagnosis'] = 8
        feedback_parts.append(f"A diagnosis was added but not a valid target code (T52.1 or D61.x)")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No relevant diagnosis added for John Zenon")

    # --- Criterion 2: Clinical Evaluation (20 pts) ---
    eval_found = result.get('eval_found', False)
    if eval_found:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append("Clinical evaluation documented")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Labs >= 3 (20 pts) ---
    try:
        lab_count = int(result.get('new_lab_count', 0))
    except (ValueError, TypeError):
        lab_count = 0
    lab_types = result.get('new_lab_types', '')
    
    if lab_count >= 3:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Hematology labs ordered: {lab_count} ({lab_types})")
    elif lab_count == 2:
        score += 14
        subscores['labs'] = 14
        feedback_parts.append(f"Only 2 labs ordered ({lab_types}), need at least 3")
    elif lab_count == 1:
        score += 7
        subscores['labs'] = 7
        feedback_parts.append(f"Only 1 lab ordered ({lab_types}), need at least 3")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No hematology labs ordered")

    # --- Criterion 4: Prescription (20 pts) ---
    presc_found = result.get('presc_found', False)
    support_found = result.get('support_found', False)
    support_drug = result.get('support_drug', 'none')
    
    if presc_found and support_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Supportive therapy prescribed: {support_drug}")
    elif presc_found:
        score += 10
        subscores['prescription'] = 10
        feedback_parts.append("Prescription created but no relevant supportive therapy (e.g. Folic acid, Vitamin B12, Iron) found")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No prescription ordered")
        
    # --- Criterion 5: Appointment 7-14 Days (20 pts) ---
    appt_found = result.get('appt_found', False)
    try:
        appt_days = int(result.get('appt_days', 0))
    except (ValueError, TypeError):
        appt_days = 0
        
    if appt_found and 7 <= appt_days <= 14:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled appropriately in {appt_days} days")
    elif appt_found:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up appointment scheduled but outside 7-14 day window ({appt_days} days)")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Determine overall status ---
    key_criteria_met = subscores.get('diagnosis', 0) > 0 and subscores.get('labs', 0) >= 14
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }