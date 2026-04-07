#!/usr/bin/env python3
"""
Verifier for wastewater_biohazard_protocol task.

This task requires the agent to document a biohazard exposure incident
in GNU Health across multiple modules (Conditions, Evaluations, Labs,
Prescriptions, Appointments).

Scoring breakdown (100 points total):
  - 20 pts: Infectious diagnosis (ICD-10 A00-A09)
  - 20 pts: Clinical evaluation with Systolic BP <= 90 and HR >= 100
  - 20 pts: At least 2 diagnostic laboratory orders
  - 20 pts: Treatment prescription (IV fluids, ORS, or appropriate antibiotic)
  - 20 pts: Follow-up appointment scheduled exactly 2-5 days from task date

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)


def verify_wastewater_biohazard_protocol(traj, env_info, task_info):
    """Verify wastewater biohazard protocol for patient Bonifacio Caput."""
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
        copy_from_env('/tmp/wastewater_biohazard_protocol_result.json', local_path)
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

    # --- Criterion 1: Infectious Diagnosis (20 pts) ---
    a0_found = result.get('a0_found', False)
    a0_code = result.get('a0_code', 'none')
    a0_active = result.get('a0_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if a0_found and a0_active:
        score += 20
        subscores['infectious_diagnosis'] = 20
        feedback_parts.append(f"Infectious intestinal disease documented: ICD-10 {a0_code} (active)")
    elif a0_found:
        score += 15
        subscores['infectious_diagnosis'] = 15
        feedback_parts.append(f"Infectious diagnosis found ({a0_code}) but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['infectious_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an intestinal infectious disease (A00-A09 range)")
    else:
        subscores['infectious_diagnosis'] = 0
        feedback_parts.append("MISSING: No intestinal infectious disease diagnosis (A00-A09) found")

    # --- Criterion 2: Clinical Evaluation Vitals (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_sys = result.get('evaluation_systolic', 'null')
    eval_hr = result.get('evaluation_heart_rate', 'null')
    
    sys_ok = False
    hr_ok = False
    
    if eval_found:
        try:
            sys_val = float(eval_sys)
            if sys_val <= 90:
                sys_ok = True
        except (ValueError, TypeError):
            pass
            
        try:
            hr_val = float(eval_hr)
            if hr_val >= 100:
                hr_ok = True
        except (ValueError, TypeError):
            pass

    if eval_found and sys_ok and hr_ok:
        score += 20
        subscores['hypovolemic_vitals'] = 20
        feedback_parts.append(f"Hypovolemic vitals documented: Systolic BP {eval_sys} (<=90), HR {eval_hr} (>=100)")
    elif eval_found and (sys_ok or hr_ok):
        score += 10
        subscores['hypovolemic_vitals'] = 10
        feedback_parts.append(f"Partial vitals: Systolic BP {eval_sys}, HR {eval_hr}. Both <=90 and >=100 required.")
    elif eval_found:
        score += 5
        subscores['hypovolemic_vitals'] = 5
        feedback_parts.append(f"Evaluation created, but vitals (Sys:{eval_sys}, HR:{eval_hr}) don't indicate severe hypovolemia.")
    else:
        subscores['hypovolemic_vitals'] = 0
        feedback_parts.append("MISSING: No clinical evaluation with vitals recorded")

    # --- Criterion 3: Laboratory Orders >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Sufficient lab orders: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['lab_orders'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — minimum 2 required")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No diagnostic laboratory tests ordered")

    # --- Criterion 4: Treatment Prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    treatment_found = result.get('treatment_found', False)
    treatment_drug = result.get('treatment_drug_name', 'none')

    if prescription_found and treatment_found:
        score += 20
        subscores['treatment_prescription'] = 20
        feedback_parts.append(f"Appropriate treatment prescribed: {treatment_drug}")
    elif prescription_found:
        score += 10
        subscores['treatment_prescription'] = 10
        feedback_parts.append("Prescription created, but not a recognized fluid resuscitation or appropriate antibiotic")
    else:
        subscores['treatment_prescription'] = 0
        feedback_parts.append("MISSING: No treatment prescription recorded")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_date_str = result.get('appointment_date', 'none')
    task_start_str = result.get('task_start_date', 'none')

    if appt_found and appt_date_str != 'none' and task_start_str != 'none':
        try:
            appt_date = datetime.strptime(appt_date_str, "%Y-%m-%d").date()
            task_date = datetime.strptime(task_start_str, "%Y-%m-%d").date()
            delta_days = (appt_date - task_date).days

            if 2 <= delta_days <= 5:
                score += 20
                subscores['follow_up'] = 20
                feedback_parts.append(f"Appropriate follow-up scheduled in {delta_days} days ({appt_date_str})")
            else:
                score += 10
                subscores['follow_up'] = 10
                feedback_parts.append(f"Follow-up scheduled in {delta_days} days — expected 2-5 days for urgent reassessment")
        except ValueError:
            score += 5
            subscores['follow_up'] = 5
            feedback_parts.append("Appointment found but date could not be parsed")
    elif appt_found:
        score += 5
        subscores['follow_up'] = 5
        feedback_parts.append("Appointment record found without valid date")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # Determine pass/fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }