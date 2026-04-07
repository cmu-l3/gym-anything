#!/usr/bin/env python3
"""
Verifier for occupational_h2s_exposure_protocol task.

This is a very_hard task. The agent must independently manage a toxicological emergency
protocol for H2S exposure across multiple EHR modules.

Scoring breakdown (100 points total):
  - 20 pts: Toxic effect of gases/vapors diagnosis (T59.x) for Roberto Carlos
  - 20 pts: Clinical evaluation with tachypnea (RR > 20) and tachycardia (HR > 100)
  - 20 pts: Bronchodilator prescription (Salbutamol, Albuterol, Ipratropium, etc.)
  - 20 pts: At least 2 toxicology/metabolic baseline lab orders
  - 20 pts: Return-to-Work clearance follow-up appointment within 1-5 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_h2s_exposure_protocol(traj, env_info, task_info):
    """Verify occupational H2S exposure management for patient Roberto Carlos."""
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
        copy_from_env('/tmp/occupational_h2s_exposure_protocol_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Roberto Carlos not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'roberto' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Roberto Carlos, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Toxic inhalation diagnosis T59.x (20 pts) ---
    t59_found = result.get('t59_found', False)
    t59_code = result.get('t59_code', 'none')
    t59_active = result.get('t59_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if t59_found and t59_active:
        score += 20
        subscores['toxicology_diagnosis'] = 20
        feedback_parts.append(f"Toxic inhalation diagnosis documented: ICD-10 {t59_code} (active)")
    elif t59_found:
        score += 15
        subscores['toxicology_diagnosis'] = 15
        feedback_parts.append(f"Diagnosis {t59_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['toxicology_diagnosis'] = 5
        feedback_parts.append(f"A diagnosis was added but not a T59.x toxic gas/fume code")
    else:
        subscores['toxicology_diagnosis'] = 0
        feedback_parts.append("MISSING: No toxic inhalation diagnosis (T59.x) for Roberto Carlos")

    # --- Criterion 2: Clinical evaluation with respiratory distress (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_tachypnea = result.get('evaluation_tachypnea', False)
    eval_tachycardia = result.get('evaluation_tachycardia', False)
    eval_rr = result.get('evaluation_rr', 'N/A')
    eval_hr = result.get('evaluation_hr', 'N/A')

    if eval_found and eval_tachypnea and eval_tachycardia:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented respiratory distress: RR={eval_rr}, HR={eval_hr}")
    elif eval_found and (eval_tachypnea or eval_tachycardia):
        score += 12
        subscores['clinical_evaluation'] = 12
        feedback_parts.append(f"Evaluation with partial vitals: RR={eval_rr} (tachypnea={eval_tachypnea}), HR={eval_hr} (tachy={eval_tachycardia})")
    elif eval_found:
        score += 6
        subscores['clinical_evaluation'] = 6
        feedback_parts.append("Evaluation created but respiratory distress vitals not documented correctly (need RR>20, HR>100)")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for H2S exposure")

    # --- Criterion 3: Bronchodilator prescription (20 pts) ---
    presc_found = result.get('prescription_found', False)
    bronchodilator_found = result.get('bronchodilator_found', False)
    bronch_name = result.get('bronchodilator_name', 'none')

    if presc_found and bronchodilator_found:
        score += 20
        subscores['bronchodilator_rx'] = 20
        feedback_parts.append(f"Bronchodilator prescribed: {bronch_name}")
    elif presc_found:
        score += 5
        subscores['bronchodilator_rx'] = 5
        feedback_parts.append("Prescription created but drug is not an inhaled bronchodilator (Salbutamol/Albuterol)")
    else:
        subscores['bronchodilator_rx'] = 0
        feedback_parts.append("MISSING: No bronchodilator prescribed for reactive airway management")

    # --- Criterion 4: Baseline toxicology labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['toxicology_labs'] = 20
        feedback_parts.append(f"Metabolic/toxicology labs ordered: {new_lab_count} tests ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['toxicology_labs'] = 10
        feedback_parts.append(f"Only 1 lab test ordered ({new_lab_types}) — exposure protocol requires at least 2")
    else:
        subscores['toxicology_labs'] = 0
        feedback_parts.append("MISSING: No diagnostic laboratory tests ordered")

    # --- Criterion 5: RTW Follow-up Appointment 1-5 days (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_days_str = result.get('appt_days', 'none')
    
    if appt_found:
        try:
            appt_days = int(appt_days_str)
            if 1 <= appt_days <= 5:
                score += 20
                subscores['rtw_followup'] = 20
                feedback_parts.append(f"RTW follow-up scheduled appropriately: in {appt_days} days")
            elif 0 <= appt_days <= 10:
                score += 10
                subscores['rtw_followup'] = 10
                feedback_parts.append(f"Follow-up scheduled but outside the 1-5 day window (in {appt_days} days)")
            else:
                score += 5
                subscores['rtw_followup'] = 5
                feedback_parts.append(f"Follow-up scheduled too far out ({appt_days} days) for acute exposure clearance")
        except ValueError:
            score += 5
            subscores['rtw_followup'] = 5
            feedback_parts.append(f"Follow-up scheduled but date could not be parsed: {appt_days_str}")
    else:
        subscores['rtw_followup'] = 0
        feedback_parts.append("MISSING: No short-term Return-to-Work clearance follow-up scheduled")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }