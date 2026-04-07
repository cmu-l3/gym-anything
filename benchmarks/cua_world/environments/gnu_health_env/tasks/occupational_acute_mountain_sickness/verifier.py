#!/usr/bin/env python3
"""
Verifier for occupational_acute_mountain_sickness task.

Scoring breakdown (100 points total):
  - 20 pts: T70.x Acute Mountain Sickness diagnosis
  - 20 pts: Clinical evaluation with Hypoxia (SpO2 <= 88%) and Tachycardia (HR >= 100 bpm)
  - 20 pts: AMS prescription (Acetazolamide or Dexamethasone)
  - 20 pts: Respiratory/Metabolic Lab (ABG / Blood Gas / Metabolic panel)
  - 20 pts: Short-interval follow-up appointment within 1-3 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_acute_mountain_sickness(traj, env_info, task_info):
    """Verify acute mountain sickness management protocol."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_acute_mountain_sickness_result.json', local_path)
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

    # Verify Patient Identity
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient Roberto Carlos not found — setup may have failed.",
            "subscores": {}
        }
    target_name = result.get('target_patient_name', '')
    if 'roberto' not in target_name.lower() or 'carlos' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Roberto Carlos, got: {target_name}",
            "subscores": {}
        }

    # 1: T70.x Diagnosis (20 pts)
    t70_found = result.get('t70_found', False)
    t70_active = result.get('t70_active', False)
    t70_code = result.get('t70_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    
    if t70_found and t70_active:
        score += 20
        subscores['ams_diagnosis'] = 20
        feedback_parts.append(f"Acute mountain sickness diagnosis documented: ICD-10 {t70_code} (active)")
    elif t70_found:
        score += 15
        subscores['ams_diagnosis'] = 15
        feedback_parts.append(f"T70.x diagnosis found but NOT marked active (code: {t70_code})")
    elif any_new_disease > 0:
        score += 5
        subscores['ams_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not a T70.x code")
    else:
        subscores['ams_diagnosis'] = 0
        feedback_parts.append("MISSING: No AMS diagnosis (T70.x) found for Roberto Carlos")

    # 2: Clinical evaluation with Hypoxia & Tachycardia (20 pts)
    eval_found = result.get('evaluation_found', False)
    eval_has_hypoxia = result.get('evaluation_has_hypoxia', False)
    eval_has_tachycardia = result.get('evaluation_has_tachycardia', False)
    eval_osat = result.get('evaluation_osat', 'N/A')
    eval_hr = result.get('evaluation_heart_rate', 'N/A')

    if eval_found and eval_has_hypoxia and eval_has_tachycardia:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented: SpO2={eval_osat}% (hypoxia), HR={eval_hr} (tachycardia)")
    elif eval_found and (eval_has_hypoxia or eval_has_tachycardia):
        score += 12
        subscores['clinical_evaluation'] = 12
        feedback_parts.append(f"Evaluation with partial vitals: SpO2={eval_osat}%, HR={eval_hr}")
    elif eval_found:
        score += 6
        subscores['clinical_evaluation'] = 6
        feedback_parts.append("Evaluation created but vital signs not documented correctly (need SpO2<=88, HR>=100)")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # 3: AMS Prescription (20 pts)
    presc_found = result.get('prescription_found', False)
    ams_rx_found = result.get('ams_rx_found', False)
    ams_drug_name = result.get('ams_drug_name', 'none')

    if presc_found and ams_rx_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"AMS prescription ordered: {ams_drug_name}")
    elif presc_found:
        score += 8
        subscores['prescription'] = 8
        feedback_parts.append("Prescription created but NOT for Acetazolamide or Dexamethasone")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No prescription found")

    # 4: Lab Order (Blood Gas/Metabolic) (20 pts)
    lab_count = result.get('lab_count', 0)
    target_lab_found = result.get('target_lab_found', False)
    target_lab_name = result.get('target_lab_name', 'none')

    if lab_count > 0 and target_lab_found:
        score += 20
        subscores['lab_order'] = 20
        feedback_parts.append(f"Appropriate lab ordered: {target_lab_name}")
    elif lab_count > 0:
        score += 8
        subscores['lab_order'] = 8
        feedback_parts.append(f"Labs ordered ({lab_count}) but no Blood Gas or Metabolic panel found")
    else:
        subscores['lab_order'] = 0
        feedback_parts.append("MISSING: No lab test ordered")

    # 5: Follow-up Appointment (20 pts)
    appt_found = result.get('appt_found', False)
    appt_days_diff = result.get('appt_days_diff', -999)
    appt_date = result.get('appt_date', 'none')

    if appt_found and 1 <= appt_days_diff <= 3:
        score += 20
        subscores['follow_up'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled appropriately in {appt_days_diff} days ({appt_date})")
    elif appt_found and appt_days_diff > 3:
        score += 10
        subscores['follow_up'] = 10
        feedback_parts.append(f"Follow-up scheduled in {appt_days_diff} days — too late for acute mountain sickness monitoring")
    elif appt_found:
        score += 5
        subscores['follow_up'] = 5
        feedback_parts.append(f"Follow-up scheduled on invalid date ({appt_date})")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "subscores": subscores
    }