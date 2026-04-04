#!/usr/bin/env python3
"""
Verifier for emergency_acute_presentation task.

This is a very_hard task. The agent must independently determine appropriate clinical
actions for an acute abdominal presentation. No step-by-step instructions are given.

Scoring breakdown (100 points total):
  - 20 pts: Emergency appointment for Luna on today's date (within ±1 day)
  - 20 pts: Clinical evaluation with fever (>=38.0°C) AND tachycardia (>=100 bpm)
  - 20 pts: At least 2 new lab test orders for Luna
  - 20 pts: Abdominal ICD-10 diagnosis (any K prefix code) documented for Luna
  - 20 pts: Short-term surgical/urgent follow-up scheduled within 7 days

Pass threshold: score >= 70 (requires 3-4 correct clinical decisions)
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_emergency_acute_presentation(traj, env_info, task_info):
    """Verify emergency workup documentation for acute abdominal presentation (patient Luna)."""
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
        copy_from_env('/tmp/emergency_acute_presentation_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Luna not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'luna' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Luna, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Emergency appointment today (20 pts) ---
    er_appt_found = result.get('er_appointment_found', False)
    er_appt_date = result.get('er_appointment_date', 'none')
    er_urgency = result.get('er_appointment_urgency', 'unknown')
    all_new_appts = result.get('all_new_appt_count', 0)

    if er_appt_found:
        score += 20
        subscores['emergency_appointment'] = 20
        feedback_parts.append(f"Emergency appointment recorded for {er_appt_date} (urgency: {er_urgency})")
    elif all_new_appts and int(all_new_appts) > 0:
        score += 10
        subscores['emergency_appointment'] = 10
        feedback_parts.append(f"An appointment was created but NOT for today's date — an ER presentation requires a same-day appointment")
    else:
        subscores['emergency_appointment'] = 0
        feedback_parts.append("MISSING: No emergency appointment created for Luna today")

    # --- Criterion 2: Clinical evaluation with fever and tachycardia (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_has_fever = result.get('evaluation_has_fever', False)
    eval_has_tachycardia = result.get('evaluation_has_tachycardia', False)
    eval_temp = result.get('evaluation_temperature', 'N/A')
    eval_hr = result.get('evaluation_heart_rate', 'N/A')

    if eval_found and eval_has_fever and eval_has_tachycardia:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with appropriate vitals: temp={eval_temp}°C (fever), HR={eval_hr} bpm (tachycardia)")
    elif eval_found and (eval_has_fever or eval_has_tachycardia):
        score += 12
        subscores['clinical_evaluation'] = 12
        feedback_parts.append(f"Clinical evaluation created but vital signs incomplete (temp={eval_temp}°C fever={eval_has_fever}, HR={eval_hr} tachy={eval_has_tachycardia})")
    elif eval_found:
        score += 6
        subscores['clinical_evaluation'] = 6
        feedback_parts.append(f"Clinical evaluation created but vital signs (fever>=38°C, HR>=100) not documented correctly")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation/encounter documented for Luna")

    # --- Criterion 3: At least 2 lab orders (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')

    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Appropriate lab workup: {new_lab_count} lab tests ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['lab_orders'] = 10
        feedback_parts.append(f"Only 1 lab test ordered ({new_lab_types}) — acute abdomen requires minimum 2 tests (e.g., CBC + CRP)")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No laboratory tests ordered for Luna (CBC and CRP are indicated for acute abdomen with fever)")

    # --- Criterion 4: Abdominal ICD-10 diagnosis (K prefix) (20 pts) ---
    k_disease_found = result.get('abdominal_diagnosis_found', False)
    k_disease_code = result.get('abdominal_diagnosis_code', 'none')

    if k_disease_found:
        # Bonus check: is it specifically an appendicitis code (K35-K38)?
        appendicitis_codes = ['K35', 'K36', 'K37', 'K38']
        is_appendicitis = any(k_disease_code.startswith(c) for c in appendicitis_codes)
        if is_appendicitis:
            score += 20
            subscores['abdominal_diagnosis'] = 20
            feedback_parts.append(f"Correct appendicitis diagnosis documented: ICD-10 {k_disease_code}")
        else:
            score += 15
            subscores['abdominal_diagnosis'] = 15
            feedback_parts.append(f"Abdominal diagnosis documented (ICD-10: {k_disease_code}) — a more specific appendicitis code (K35-K38) would be ideal")
    else:
        subscores['abdominal_diagnosis'] = 0
        feedback_parts.append("MISSING: No abdominal ICD-10 diagnosis (K-prefix code) documented for Luna (acute appendicitis = K35/K37)")

    # --- Criterion 5: Short-term surgical follow-up within 7 days (20 pts) ---
    surgical_found = result.get('surgical_followup_found', False)
    surgical_date = result.get('surgical_followup_date', 'none')
    followup_max = result.get('followup_max_window', '')

    if surgical_found:
        score += 20
        subscores['surgical_followup'] = 20
        feedback_parts.append(f"Surgical/urgent consultation scheduled for {surgical_date} (within 7-day window)")
    elif all_new_appts and int(all_new_appts) >= 2:
        # If there were 2+ appointments, maybe one was for follow-up but wrong date
        score += 8
        subscores['surgical_followup'] = 8
        feedback_parts.append("Multiple appointments scheduled but no short-term (1-7 day) surgical consultation found")
    else:
        subscores['surgical_followup'] = 0
        feedback_parts.append(f"MISSING: No urgent surgical follow-up appointment within 7 days (appendicitis requires immediate surgical evaluation)")

    # --- Final result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "target_patient": target_name,
        "clinical_note": "Acute RLQ pain + fever + McBurney's tenderness = acute appendicitis requiring CBC/CRP labs + K35/K37 diagnosis + urgent surgical consult"
    }
