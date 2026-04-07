#!/usr/bin/env python3
"""
Verifier for occupational_photokeratitis_management task.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_photokeratitis_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_photokeratitis_management_result.json', local_path)
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
    target_name = result.get('target_patient_name', '')
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient John Zenon not found — setup may have failed.",
            "subscores": {}
        }
    if 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # Criterion 1: Photokeratitis diagnosis (20 pts)
    disease_found = result.get('disease_found', False)
    disease_active = result.get('disease_active', False)
    disease_code = result.get('disease_code', 'none')
    any_new_disease = int(result.get('any_new_disease_count', 0))

    if disease_found and disease_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Diagnosis documented: ICD-10 {disease_code} (active)")
    elif disease_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Diagnosis {disease_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append(f"A diagnosis was added but not an H16 or T26 code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No photokeratitis diagnosis (H16.x or T26.x) for John Zenon")

    # Criterion 2: Clinical Evaluation (20 pts)
    eval_found = result.get('evaluation_found', False)
    if eval_found:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append("Clinical evaluation documented")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 3 & 4: Prescriptions (NSAID & Antibiotic)
    new_drugs_str = result.get('new_drugs_list', '').lower()
    total_presc = int(result.get('total_new_prescriptions', 0))
    
    nsaids = [x.lower() for x in metadata.get('nsaid_options', ["ibuprofen", "diclofenac", "naproxen", "ketorolac", "meloxicam", "celecoxib"])]
    antibiotics = [x.lower() for x in metadata.get('antibiotic_options', ["erythromycin", "tetracycline", "ciprofloxacin", "tobramycin", "ofloxacin", "gentamicin", "azithromycin", "polymyxin", "bacitracin", "moxifloxacin"])]
    
    nsaid_found = any(nsaid in new_drugs_str for nsaid in nsaids)
    abx_found = any(abx in new_drugs_str for abx in antibiotics)

    if nsaid_found:
        score += 20
        subscores['nsaid'] = 20
        feedback_parts.append("Oral NSAID prescribed")
    elif total_presc > 0:
        score += 5
        subscores['nsaid'] = 5
        feedback_parts.append("Prescription created but no matching NSAID found")
    else:
        subscores['nsaid'] = 0
        feedback_parts.append("MISSING: No oral NSAID prescribed")

    if abx_found:
        score += 20
        subscores['antibiotic'] = 20
        feedback_parts.append("Topical antibiotic prescribed")
    elif total_presc > 0 and not nsaid_found: # Prevent double penalizing the fallback
        score += 5
        subscores['antibiotic'] = 5
        feedback_parts.append("Prescription created but no matching antibiotic found")
    else:
        subscores['antibiotic'] = 0
        feedback_parts.append("MISSING: No topical antibiotic prescribed")

    # Criterion 5: Appointment 1-2 days (20 pts)
    appt_found = result.get('appointment_found', False)
    appt_diff = result.get('appointment_diff_days', 'null')
    
    try:
        diff_val = int(appt_diff)
    except (ValueError, TypeError):
        diff_val = -999

    min_days = metadata.get('followup_min_days', 1)
    max_days = metadata.get('followup_max_days', 3)  # Accept 3 as grace

    if appt_found and min_days <= diff_val <= max_days:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled appropriately ({diff_val} days from today)")
    elif appt_found:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Appointment scheduled but wrong timeframe ({diff_val} days; expected 1-2 days)")
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