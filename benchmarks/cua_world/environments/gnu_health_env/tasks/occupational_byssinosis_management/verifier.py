#!/usr/bin/env python3
"""
Verifier for occupational_byssinosis_management task.

This task requires the agent to document an occupational lung disease exposure
across multiple EHR modules (Conditions, Evaluations, Labs, Pharmacy, Appointments).

Scoring breakdown (100 points total):
  - 20 pts: Byssinosis diagnosis (J66.x) for Ana Isabel Betz
  - 20 pts: Clinical evaluation documenting 'chest tightness' / 'cough'
  - 20 pts: At least 2 diagnostic tests ordered
  - 20 pts: Respiratory medication prescribed
  - 20 pts: Follow-up appointment scheduled in 14-30 days

Pass threshold: score >= 70, with mandatory J66 and evaluation components.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_byssinosis_management(traj, env_info, task_info):
    """Verify occupational byssinosis management for patient Ana Isabel Betz."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Verify Agent VLM Trajectory (Anti-Gaming Check) ---
    used_ui = True
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames and env_info.get('query_vlm'):
            prompt = "Look at these screenshots from a workflow in the GNU Health web application. Did the user actually navigate the web interface to view/edit patient records, conditions, or evaluations? Reply strictly with JSON: {\"used_web_ui\": true/false}"
            vlm_res = env_info['query_vlm'](images=frames, prompt=prompt)
            if vlm_res and 'parsed' in vlm_res:
                used_ui = vlm_res['parsed'].get('used_web_ui', True)
    except Exception as e:
        logger.warning(f"VLM trajectory check skipped or failed: {e}")

    if not used_ui:
        return {
            "passed": False,
            "score": 0,
            "feedback": "VLM verification failed: The agent did not appear to use the GNU Health graphical interface to complete the task.",
            "subscores": {}
        }

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_byssinosis_management_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Ana Isabel Betz not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'ana' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Ana Betz, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: J66.x Byssinosis Diagnosis (20 pts) ---
    j66_found = result.get('j66_found', False)
    j66_active = result.get('j66_active', False)
    j66_code = result.get('j66_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except:
        any_new_disease = 0

    if j66_found and j66_active:
        score += 20
        subscores['byssinosis_diagnosis'] = 20
        feedback_parts.append(f"Byssinosis diagnosis documented: ICD-10 {j66_code} (active)")
    elif j66_found:
        score += 15
        subscores['byssinosis_diagnosis'] = 15
        feedback_parts.append(f"J66 diagnosis found but not marked active (code: {j66_code})")
    elif any_new_disease > 0:
        score += 5
        subscores['byssinosis_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but it was not the required J66 code for Byssinosis")
    else:
        subscores['byssinosis_diagnosis'] = 0
        feedback_parts.append("MISSING: No Byssinosis diagnosis (J66.x) found for Ana Betz")

    # --- Criterion 2: Clinical Evaluation (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_has_chest = result.get('evaluation_has_chest', False)
    eval_has_cough = result.get('evaluation_has_cough', False)

    if eval_found and eval_has_chest and eval_has_cough:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append("Clinical evaluation documented containing both 'chest/tightness' and 'cough'")
    elif eval_found and (eval_has_chest or eval_has_cough):
        score += 15
        subscores['clinical_evaluation'] = 15
        feedback_parts.append("Clinical evaluation created but missing some required symptoms (chest tightness or cough)")
    elif eval_found:
        score += 10
        subscores['clinical_evaluation'] = 10
        feedback_parts.append("Evaluation created, but required respiratory symptoms not found in chief complaint")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Diagnostic Labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except:
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['diagnostic_labs'] = 20
        feedback_parts.append(f"Adequate diagnostic tests ordered: {new_lab_count} ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['diagnostic_labs'] = 10
        feedback_parts.append(f"Only 1 diagnostic test ordered ({new_lab_types}) — expected at least 2")
    else:
        subscores['diagnostic_labs'] = 0
        feedback_parts.append("MISSING: No diagnostic tests ordered")

    # --- Criterion 4: Respiratory Medication (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    resp_med_found = result.get('respiratory_med_found', False)
    resp_drug = result.get('respiratory_drug_name', 'none')

    if prescription_found and resp_med_found:
        score += 20
        subscores['respiratory_med'] = 20
        feedback_parts.append(f"Respiratory medication prescribed: {resp_drug}")
    elif prescription_found:
        score += 10
        subscores['respiratory_med'] = 10
        feedback_parts.append("Prescription created but no matching respiratory medication (albuterol/fluticasone/etc.) found")
    else:
        subscores['respiratory_med'] = 0
        feedback_parts.append("MISSING: No prescription documented")

    # --- Criterion 5: Follow-up Appointment in 14-30 days (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_diff = result.get('appointment_diff_days', -999)
    try:
        appt_diff = float(appt_diff)
    except:
        appt_diff = -999

    if appt_found and 13.0 <= appt_diff <= 31.0: # lenient by 1 day
        score += 20
        subscores['followup_appointment'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled appropriately ({int(appt_diff)} days out)")
    elif appt_found:
        score += 10
        subscores['followup_appointment'] = 10
        feedback_parts.append(f"Appointment scheduled, but {int(appt_diff)} days out is not within the requested 14-30 day window")
    else:
        subscores['followup_appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # Determine passing based on score and mandatory elements
    mandatory_met = (j66_found and eval_found)
    passed = (score >= 70) and mandatory_met

    if score >= 70 and not mandatory_met:
        feedback_parts.append("FAILED: Met point threshold but missing mandatory core actions (Diagnosis & Evaluation)")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }