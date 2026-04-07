#!/usr/bin/env python3
"""
Verifier for occupational_asthma_management task.

Scoring breakdown (100 points total):
  - 20 pts: Occupational asthma diagnosis (J45.x) for John Zenon
  - 20 pts: Clinical evaluation with Respiratory Rate >= 22 AND SpO2 <= 94%
  - 20 pts: Rescue inhaler prescription (Salbutamol, Albuterol, Budesonide, etc.)
  - 20 pts: At least 2 baseline lab orders
  - 20 pts: Pulmonology follow-up appointment within 14-30 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_asthma_management(traj, env_info, task_info):
    """Verify occupational asthma protocol for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_asthma_management_result.json', local_path)
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
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient John Zenon not found — setup may have failed.",
            "subscores": {}
        }

    # Criterion 1: J45 Asthma diagnosis (20 pts)
    j45_found = result.get('j45_found', False)
    j45_active = result.get('j45_active', False)
    j45_code = result.get('j45_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)

    if j45_found and j45_active:
        score += 20
        subscores['asthma_diagnosis'] = 20
        feedback_parts.append(f"Asthma diagnosis documented: ICD-10 {j45_code} (active)")
    elif j45_found:
        score += 15
        subscores['asthma_diagnosis'] = 15
        feedback_parts.append(f"J45 Asthma diagnosis found but NOT marked active (code: {j45_code})")
    elif any_new_disease > 0:
        score += 8
        subscores['asthma_diagnosis'] = 8
        feedback_parts.append("A diagnosis was added but not a J45 asthma code")
    else:
        subscores['asthma_diagnosis'] = 0
        feedback_parts.append("MISSING: No asthma diagnosis (J45.x) found for John Zenon")

    # Criterion 2: Clinical evaluation with RR >= 22 and SpO2 <= 94 (20 pts)
    eval_found = result.get('evaluation_found', False)
    eval_rr_str = result.get('evaluation_rr', 'null')
    eval_osat_str = result.get('evaluation_osat', 'null')
    any_new_eval = result.get('any_new_eval_count', 0)
    
    rr_value = None
    osat_value = None
    try:
        if eval_rr_str and eval_rr_str != 'null':
            rr_value = float(eval_rr_str)
        if eval_osat_str and eval_osat_str != 'null':
            osat_value = float(eval_osat_str)
    except ValueError:
        pass

    has_rr_distress = rr_value is not None and rr_value >= 22
    has_osat_distress = osat_value is not None and osat_value <= 94

    if eval_found and has_rr_distress and has_osat_distress:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented: RR={rr_value}, SpO2={osat_value}%")
    elif eval_found and (has_rr_distress or has_osat_distress):
        score += 12
        subscores['clinical_evaluation'] = 12
        feedback_parts.append(f"Evaluation with partial distress vitals: RR={rr_value}, SpO2={osat_value}%")
    elif eval_found or any_new_eval > 0:
        score += 6
        subscores['clinical_evaluation'] = 6
        feedback_parts.append(f"Evaluation created but respiratory distress vitals (RR>=22, SpO2<=94) not properly documented")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for John Zenon")

    # Criterion 3: Rescue inhaler prescription (20 pts)
    prescription_found = result.get('prescription_found', False)
    saba_found = result.get('saba_found', False)
    saba_name = result.get('saba_name', 'none')

    if prescription_found and saba_found:
        score += 20
        subscores['rescue_inhaler_rx'] = 20
        feedback_parts.append(f"Rescue inhaler prescribed: {saba_name}")
    elif prescription_found:
        score += 10
        subscores['rescue_inhaler_rx'] = 10
        feedback_parts.append("Prescription created but no matching SABA/ICS (Salbutamol, Albuterol, Budesonide, etc.) identified")
    else:
        subscores['rescue_inhaler_rx'] = 0
        feedback_parts.append("MISSING: No rescue inhaler prescribed")

    # Criterion 4: Baseline labs >= 2 (20 pts)
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')

    if new_lab_count >= 2:
        score += 20
        subscores['baseline_labs'] = 20
        feedback_parts.append(f"Baseline lab orders: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['baseline_labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — expected at least 2")
    else:
        subscores['baseline_labs'] = 0
        feedback_parts.append("MISSING: No baseline labs ordered")

    # Criterion 5: Follow-up appointment 14-30 days (20 pts)
    appt_found = result.get('appointment_found', False)
    appt_days_str = result.get('appointment_days_from_start', 'null')
    
    appt_days = None
    try:
        if appt_days_str and appt_days_str != 'null':
            appt_days = float(appt_days_str)
    except ValueError:
        pass

    if appt_found and appt_days is not None:
        if 14 <= appt_days <= 30:
            score += 20
            subscores['followup_appt'] = 20
            feedback_parts.append(f"Follow-up appointment scheduled appropriately ({appt_days} days out)")
        elif appt_days > 0:
            score += 10
            subscores['followup_appt'] = 10
            feedback_parts.append(f"Appointment scheduled but interval incorrect ({appt_days} days out, expected 14-30)")
        else:
            score += 5
            subscores['followup_appt'] = 5
            feedback_parts.append("Appointment scheduled but interval could not be properly verified")
    else:
        subscores['followup_appt'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # Success logic
    key_criteria_met = j45_found and (saba_found or new_lab_count > 0)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }