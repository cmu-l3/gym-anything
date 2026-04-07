#!/usr/bin/env python3
"""
Verifier for occupational_respirator_medical_clearance task.

This task requires the agent to complete a prophylactic medical clearance workflow:
1. Z-code administrative diagnosis
2. Clinical evaluation with baseline HR and RR
3. Diagnostic Imaging Order
4. Laboratory Order
5. Fit test appointment (7-14 days in future)
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)


def build_trajectory_prompt():
    return """Examine these screenshots from an agent's trajectory.
Did the agent actively use the GNU Health or Tryton web interface to perform tasks?
Look for indications of form filling, menu navigation, or patient searching within the browser.
Respond with a JSON object containing a single boolean field:
{"used_ui": true} or {"used_ui": false}
"""


def verify_occupational_respirator_medical_clearance(traj, env_info, task_info):
    """Verify occupational respirator medical clearance for patient John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Extract metadata
    metadata = task_info.get('metadata', {})
    min_imaging = metadata.get('min_imaging_orders', 1)
    min_labs = metadata.get('min_lab_orders', 1)
    min_days = metadata.get('followup_min_days', 7)
    max_days = metadata.get('followup_max_days', 14)

    score = 0
    feedback_parts = []
    subscores = {}

    # Read result from environment
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/task_result.json', local_path)
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

    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patient not found — setup may have failed.",
            "subscores": {}
        }

    # --- Criterion 1: Administrative Diagnosis (Z02.x or Z10.x) (20 pts) ---
    z_found = result.get('z_code_found', False)
    z_code = result.get('z_code', 'none')
    z_active = result.get('z_code_active', False)
    any_new_disease = int(result.get('any_new_disease_count', 0))

    if z_found and z_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Administrative diagnosis documented: {z_code} (active)")
    elif z_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Z-code diagnosis documented ({z_code}) but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but it was not an appropriate occupational Z-code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No administrative diagnosis (Z02/Z10) found")

    # --- Criterion 2: Clinical Evaluation (20 pts) ---
    eval_found = result.get('eval_found', False)
    eval_hr = result.get('eval_hr', 'null')
    eval_rr = result.get('eval_rr', 'null')

    if eval_found and eval_hr != 'null' and eval_rr != 'null':
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append(f"Evaluation documented with vitals (HR: {eval_hr}, RR: {eval_rr})")
    elif eval_found:
        score += 10
        subscores['evaluation'] = 10
        feedback_parts.append("Evaluation created but missing required Heart Rate or Respiratory Rate")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Diagnostic Imaging Order (20 pts) ---
    imaging_count = int(result.get('new_imaging_count', 0))
    if imaging_count >= min_imaging:
        score += 20
        subscores['imaging'] = 20
        feedback_parts.append(f"Diagnostic imaging request ordered ({imaging_count} found)")
    else:
        subscores['imaging'] = 0
        feedback_parts.append("MISSING: No imaging test requested")

    # --- Criterion 4: Laboratory Order (20 pts) ---
    lab_count = int(result.get('new_lab_count', 0))
    if lab_count >= min_labs:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Laboratory test requested ({lab_count} found)")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No lab test requested")

    # --- Criterion 5: Fit Test Appointment (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_date_str = result.get('appt_date', 'null')
    task_start_date_str = result.get('task_start_date', '')

    if appt_found and appt_date_str != 'null' and task_start_date_str:
        try:
            appt_date = datetime.strptime(appt_date_str, "%Y-%m-%d").date()
            start_date = datetime.strptime(task_start_date_str, "%Y-%m-%d").date()
            days_diff = (appt_date - start_date).days

            if min_days <= days_diff <= max_days:
                score += 20
                subscores['appointment'] = 20
                feedback_parts.append(f"Appointment scheduled appropriately ({days_diff} days from start)")
            else:
                score += 10
                subscores['appointment'] = 10
                feedback_parts.append(f"Appointment scheduled, but {days_diff} days out (expected {min_days}-{max_days})")
        except ValueError:
            score += 10
            subscores['appointment'] = 10
            feedback_parts.append("Appointment found, but date parsing failed")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Optional VLM Anti-Gaming Check (Ensure UI was used) ---
    vlm_feedback = ""
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        if 'query_vlm' in env_info:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = [img for img in frames + [final] if img]
            if images:
                vlm_res = env_info['query_vlm'](images=images, prompt=build_trajectory_prompt())
                parsed = vlm_res.get('parsed', {})
                if not parsed.get('used_ui', True):
                    score = int(score * 0.5)  # Penalize 50% if they skipped UI (e.g., pure SQL hack)
                    vlm_feedback = " [PENALTY: VLM indicates UI was not used properly.]"
    except Exception as e:
        logger.warning(f"VLM trajectory check failed or not available: {e}")

    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + vlm_feedback,
        "subscores": subscores
    }