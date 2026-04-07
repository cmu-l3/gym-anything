#!/usr/bin/env python3
"""
Verifier for occupational_co_toxicity_protocol task.

This task verifies the agent's ability to document an occupational health
incident comprehensively. 

Scoring breakdown (100 points total):
  - 20 pts: Clinical evaluation with HR >= 100 and O2 Sat <= 95
  - 20 pts: Diagnosis of carbon monoxide toxicity (T59.x, active)
  - 20 pts: At least 2 new lab orders
  - 20 pts: At least 1 new prescription
  - 20 pts: Follow-up appointment scheduled in 1 to 7 days

Pass threshold: 80 points with both Evaluation and Diagnosis passed.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_occupational_co_toxicity_protocol(traj, env_info, task_info):
    """Verify occupational carbon monoxide exposure workflow."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_co_toxicity_protocol_result.json', local_path)
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

    # CRITICAL CHECK: Target Patient Match
    target_id = result.get('target_patient_id', 0)
    target_name = result.get('target_patient_name', '')
    if not target_id or 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Patient John Zenon not found or targeted correctly. Found: {target_name}",
            "subscores": {}
        }

    # 1. Evaluate Clinical Evaluation (20 pts)
    eval_found = result.get('evaluation_found', False)
    eval_hr_str = result.get('evaluation_hr', 'null')
    eval_osat_str = result.get('evaluation_osat', 'null')
    
    hr_passed = False
    osat_passed = False
    
    if eval_found:
        try:
            hr = float(eval_hr_str)
            if hr >= 100:
                hr_passed = True
        except ValueError:
            pass
            
        try:
            osat = float(eval_osat_str)
            if osat <= 95:
                osat_passed = True
        except ValueError:
            pass
            
        if hr_passed and osat_passed:
            score += 20
            subscores['clinical_evaluation'] = 20
            feedback_parts.append(f"Evaluation documented correctly: HR={eval_hr_str}, O2 Sat={eval_osat_str}")
        elif hr_passed or osat_passed:
            score += 10
            subscores['clinical_evaluation'] = 10
            feedback_parts.append(f"Evaluation documented with partial vitals: HR={eval_hr_str}, O2 Sat={eval_osat_str}")
        else:
            score += 5
            subscores['clinical_evaluation'] = 5
            feedback_parts.append(f"Evaluation created but vitals are incorrect: HR={eval_hr_str}, O2 Sat={eval_osat_str}")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for John Zenon.")

    # 2. Evaluate Diagnosis (20 pts)
    t59_found = result.get('t59_found', False)
    t59_active = result.get('t59_active', False)
    t59_code = result.get('t59_code', 'none')
    any_new_disease = int(result.get('any_new_disease_count', 0))

    if t59_found and t59_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Carbon Monoxide toxicity diagnosis documented: ICD-10 {t59_code} (active)")
    elif t59_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"T59.x diagnosis found ({t59_code}) but not marked as active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but not a T59 carbon monoxide toxicity code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No carbon monoxide toxicity diagnosis (T59.x) found.")

    # 3. Evaluate Labs (20 pts)
    lab_count = int(result.get('new_lab_count', 0))
    if lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Sufficient lab orders created: {lab_count}")
    elif lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append("Only 1 lab order created (minimum 2 required)")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No lab tests ordered")

    # 4. Evaluate Prescriptions (20 pts)
    presc_count = int(result.get('new_prescription_count', 0))
    if presc_count >= 1:
        score += 20
        subscores['prescriptions'] = 20
        feedback_parts.append(f"Prescription created: {presc_count}")
    else:
        subscores['prescriptions'] = 0
        feedback_parts.append("MISSING: No medications prescribed")

    # 5. Evaluate Appointments (20 pts)
    appt_found = result.get('appointment_found', False)
    appt_date_str = result.get('appointment_date', 'null')
    task_start_str = result.get('task_start_date', '')
    
    if appt_found and appt_date_str != 'null' and task_start_str:
        try:
            start_date = datetime.strptime(task_start_str, "%Y-%m-%d").date()
            appt_date = datetime.strptime(appt_date_str, "%Y-%m-%d").date()
            days_diff = (appt_date - start_date).days
            
            if 1 <= days_diff <= 7:
                score += 20
                subscores['appointment'] = 20
                feedback_parts.append(f"Follow-up appointment scheduled correctly in {days_diff} days")
            else:
                score += 10
                subscores['appointment'] = 10
                feedback_parts.append(f"Appointment scheduled, but {days_diff} days away (expected 1 to 7 days)")
        except ValueError:
            score += 5
            subscores['appointment'] = 5
            feedback_parts.append("Appointment found but date formatting was invalid")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # Final Pass/Fail logic
    key_criteria_met = (subscores.get('clinical_evaluation', 0) >= 10 and 
                        subscores.get('diagnosis', 0) >= 15)
    
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }