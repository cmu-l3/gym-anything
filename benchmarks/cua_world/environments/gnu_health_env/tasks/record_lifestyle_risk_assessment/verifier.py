#!/usr/bin/env python3
"""
Verifier for record_lifestyle_risk_assessment task.

This is a very_hard task. The agent must independently navigate the Lifestyle module
to update multiple risk factors, then perform clinical coding (F17), prescribing, 
lab ordering, and scheduling.

Scoring breakdown (100 points total):
  - 20 pts: Lifestyle risk factors updated correctly (4 pts per field)
  - 20 pts: F17 Tobacco Use Disorder diagnosis
  - 20 pts: Cessation prescription (Nicotine/Varenicline/Bupropion)
  - 20 pts: At least 2 baseline lab orders
  - 20 pts: Reassessment appointment 45-90 days out

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)


def verify_record_lifestyle_risk_assessment(traj, env_info, task_info):
    """Verify occupational health screening protocol for Bonifacio Caput."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_lifestyle_risk_assessment_result.json', local_path)
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
    if 'bonifacio' not in target_name.lower() or 'caput' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Bonifacio Caput, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Lifestyle Fields (20 pts) ---
    lifestyle = result.get('lifestyle', {})
    smoker = str(lifestyle.get('smoking', '')).lower() in ['t', 'true', '1']
    alcohol = str(lifestyle.get('alcohol', '')).lower() in ['t', 'true', '1']
    exercise = str(lifestyle.get('exercise', '')).lower() in ['t', 'true', '1']
    
    try:
        smoking_num = int(float(lifestyle.get('smoking_number', 0)))
    except (ValueError, TypeError):
        smoking_num = 0
        
    try:
        sleep_hours = int(float(lifestyle.get('sleep_hours', 0)))
    except (ValueError, TypeError):
        sleep_hours = 0

    lf_score = 0
    lf_feedback = []

    if smoker:
        lf_score += 4
        lf_feedback.append("Smoking=True")
    if 10 <= smoking_num <= 20:
        lf_score += 4
        lf_feedback.append(f"Cigs/day={smoking_num}")
    elif smoking_num > 0:
        lf_score += 2
        lf_feedback.append(f"Cigs/day={smoking_num} (expected ~15)")
        
    if not exercise:
        lf_score += 4
        lf_feedback.append("Exercise=False")
        
    if alcohol:
        lf_score += 4
        lf_feedback.append("Alcohol=True")
        
    if 4 <= sleep_hours <= 6:
        lf_score += 4
        lf_feedback.append(f"Sleep={sleep_hours}h")

    score += lf_score
    subscores['lifestyle'] = lf_score
    if lf_score > 0:
        feedback_parts.append(f"Lifestyle updated: {', '.join(lf_feedback)}")
    else:
        feedback_parts.append("MISSING: Lifestyle risk factors were not updated")

    # --- Criterion 2: F17 Diagnosis (20 pts) ---
    f17_found = result.get('f17_found', False)
    f17_active = result.get('f17_active', False)
    f17_code = result.get('f17_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)

    if f17_found and f17_active:
        score += 20
        subscores['f17_diagnosis'] = 20
        feedback_parts.append(f"Tobacco use disorder diagnosis documented: ICD-10 {f17_code} (active)")
    elif f17_found:
        score += 12
        subscores['f17_diagnosis'] = 12
        feedback_parts.append(f"F17 diagnosis found ({f17_code}) but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['f17_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an F17 code")
    else:
        subscores['f17_diagnosis'] = 0
        feedback_parts.append("MISSING: No F17.x diagnosis for Tobacco use disorder")

    # --- Criterion 3: Cessation Prescription (20 pts) ---
    presc_found = result.get('prescription_found', False)
    cessation_found = result.get('cessation_found', False)
    cessation_name = result.get('cessation_drug_name', 'none')

    if cessation_found:
        score += 20
        subscores['cessation_rx'] = 20
        feedback_parts.append(f"Cessation prescription ordered: {cessation_name}")
    elif presc_found:
        score += 5
        subscores['cessation_rx'] = 5
        feedback_parts.append("Prescription created but drug does not match Nicotine/Varenicline/Bupropion")
    else:
        subscores['cessation_rx'] = 0
        feedback_parts.append("MISSING: No smoking cessation medication prescribed")

    # --- Criterion 4: Baseline Labs (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')

    if new_lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Baseline labs ordered: {new_lab_count} ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — needed at least 2")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No baseline screening labs ordered")

    # --- Criterion 5: Reassessment Follow-up Appt (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_date_str = result.get('appt_date', '')
    start_date_str = result.get('task_start_date', '')

    if appt_found and appt_date_str and start_date_str:
        try:
            appt_date = datetime.strptime(appt_date_str, '%Y-%m-%d')
            start_date = datetime.strptime(start_date_str, '%Y-%m-%d')
            days_diff = (appt_date - start_date).days

            if 45 <= days_diff <= 90:
                score += 20
                subscores['follow_up'] = 20
                feedback_parts.append(f"Follow-up scheduled correctly in {days_diff} days")
            elif 30 <= days_diff <= 120:
                score += 10
                subscores['follow_up'] = 10
                feedback_parts.append(f"Follow-up scheduled in {days_diff} days (target was 45-90 days)")
            else:
                score += 5
                subscores['follow_up'] = 5
                feedback_parts.append(f"Follow-up scheduled in {days_diff} days (too far outside target range)")
        except ValueError:
            score += 5
            subscores['follow_up'] = 5
            feedback_parts.append(f"Appointment created but date parsing failed: {appt_date_str}")
    elif appt_found:
        score += 5
        subscores['follow_up'] = 5
        feedback_parts.append("Appointment found but missing valid date")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No reassessment appointment scheduled")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }