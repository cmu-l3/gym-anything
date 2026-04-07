#!/usr/bin/env python3
"""
Verifier for occupational_hearing_conservation task.

Scoring breakdown (100 points total):
  - 20 pts: Z57.0 Occupational noise exposure diagnosis for John Zenon
  - 20 pts: H90.x Sensorineural hearing loss diagnosis
  - 20 pts: Clinical evaluation containing complete basic vitals (BP + HR)
  - 20 pts: At least 2 metabolic/screening lab orders
  - 20 pts: Retest appointment scheduled between 21-30 days from today

Also incorporates VLM trajectory verification as an anti-gaming check.
Pass threshold: score >= 70 AND target patient correctly manipulated.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def build_trajectory_prompt():
    return """Examine these trajectory screenshots from a web-based Hospital Information System.
The agent was asked to manage an occupational hearing loss case for patient 'John Zenon'.

Check for evidence that the agent actually interacted with the UI:
1. Did the agent navigate to John Zenon's patient record?
2. Did the agent navigate through different modules like 'Diseases', 'Evaluations', 'Lab Test Requests', or 'Appointments'?
3. Is there evidence of data entry (typing into forms, clicking save, etc.)?

Respond in JSON format:
{
    "interacted_with_patient_record": true/false,
    "navigated_modules": true/false,
    "evidence_of_data_entry": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""


def verify_occupational_hearing_conservation(traj, env_info, task_info):
    """Verify occupational hearing conservation protocol for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Framework error: copy_from_env not available",
            "subscores": {}
        }

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_hearing_conservation_result.json', local_path)
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

    # --- Anti-Gaming: Check Correct Patient Target ---
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient John Zenon not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Z57.0 Occupational noise exposure (20 pts) ---
    z57_found = result.get('z57_found', False)
    z57_active = result.get('z57_active', False)
    z57_code = result.get('z57_code', 'none')

    if z57_found and z57_active:
        score += 20
        subscores['exposure_code'] = 20
        feedback_parts.append(f"Occupational noise exposure documented: ICD-10 {z57_code} (active)")
    elif z57_found:
        score += 15
        subscores['exposure_code'] = 15
        feedback_parts.append(f"Z57.0 exposure documented but not marked active")
    else:
        subscores['exposure_code'] = 0
        feedback_parts.append("MISSING: No occupational noise exposure diagnosis (Z57.0) found")

    # --- Criterion 2: H90.x Hearing Loss diagnosis (20 pts) ---
    h90_found = result.get('h90_found', False)
    h90_active = result.get('h90_active', False)
    h90_code = result.get('h90_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except:
        any_new_disease = 0

    if h90_found and h90_active:
        score += 20
        subscores['diagnosis_code'] = 20
        feedback_parts.append(f"Hearing loss diagnosis documented: ICD-10 {h90_code} (active)")
    elif h90_found:
        score += 15
        subscores['diagnosis_code'] = 15
        feedback_parts.append(f"H90.x diagnosis found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis_code'] = 5
        feedback_parts.append("A diagnosis was added but not a hearing loss H-code")
    else:
        subscores['diagnosis_code'] = 0
        feedback_parts.append("MISSING: No hearing loss diagnosis (H90.x) found")

    # --- Criterion 3: Clinical Evaluation w/ Vitals (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_sys = result.get('evaluation_systolic', 'null')
    eval_dia = result.get('evaluation_diastolic', 'null')
    eval_hr = result.get('evaluation_heart_rate', 'null')

    has_bp = eval_sys != 'null' and eval_dia != 'null'
    has_hr = eval_hr != 'null'

    if eval_found and has_bp and has_hr:
        score += 20
        subscores['evaluation_vitals'] = 20
        feedback_parts.append(f"Evaluation documented with complete vitals (BP {eval_sys}/{eval_dia}, HR {eval_hr})")
    elif eval_found and (has_bp or has_hr):
        score += 12
        subscores['evaluation_vitals'] = 12
        feedback_parts.append(f"Evaluation documented but missing some vitals (BP: {eval_sys}/{eval_dia}, HR: {eval_hr})")
    elif eval_found:
        score += 5
        subscores['evaluation_vitals'] = 5
        feedback_parts.append("Evaluation documented but NO vitals recorded")
    else:
        subscores['evaluation_vitals'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 4: Metabolic Lab Orders >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except:
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['lab_orders'] = 20
        feedback_parts.append(f"Lab orders sufficient: {new_lab_count} ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['lab_orders'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}), requirement is >= 2")
    else:
        subscores['lab_orders'] = 0
        feedback_parts.append("MISSING: No lab tests ordered")

    # --- Criterion 5: Retest Appointment 21-30 days out (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_days_out = result.get('appointment_days_out', 0)
    try:
        appt_days_out = int(appt_days_out)
    except:
        appt_days_out = 0

    if appt_found and 21 <= appt_days_out <= 30:
        score += 20
        subscores['follow_up'] = 20
        feedback_parts.append(f"Retest appointment scheduled correctly: {appt_days_out} days out")
    elif appt_found and (14 <= appt_days_out <= 40):
        score += 12
        subscores['follow_up'] = 12
        feedback_parts.append(f"Appointment scheduled, but slightly outside target window: {appt_days_out} days out")
    elif appt_found:
        score += 5
        subscores['follow_up'] = 5
        feedback_parts.append(f"Appointment scheduled but far outside target window: {appt_days_out} days out")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- VLM Trajectory Verification (Anti-Gaming) ---
    try:
        from gym_anything.vlm import sample_trajectory_frames
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_result = query_vlm(
                    prompt=build_trajectory_prompt(),
                    images=frames,
                    json_format=True
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('interacted_with_patient_record') and parsed.get('evidence_of_data_entry'):
                        feedback_parts.append("VLM Verification: Valid UI interactions detected")
                    else:
                        feedback_parts.append("VLM WARNING: Trajectory lacks clear evidence of UI interaction")
                        # Severe penalty if DB says task complete but VLM sees nothing
                        if score >= 60:
                            score -= 30
                            feedback_parts.append("PENALTY applied: Possible raw SQL injection detected")
    except Exception as e:
        logger.warning(f"VLM trajectory verification failed/skipped: {e}")

    # Ensure app was running
    if not result.get('app_running', True):
        feedback_parts.append("WARNING: Application was not running at end of task")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }