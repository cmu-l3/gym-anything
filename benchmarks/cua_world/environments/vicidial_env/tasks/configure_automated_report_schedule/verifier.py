#!/usr/bin/env python3
"""
Verifier for configure_automated_report_schedule task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_automated_report_schedule(traj, env_info, task_info):
    """
    Verifies that the scheduled reports feature is enabled and the specific report is scheduled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_id = metadata.get('target_scheduled_id', 'DAILY_LOG')
    target_report = metadata.get('target_report_id', 'export_calls_report')
    target_email = metadata.get('target_email', 'compliance@valleyhealth.org')
    target_time = metadata.get('target_run_time', '0200')
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: System Setting Enabled (30 pts)
    # The value comes from MySQL as a string "1" or "0"
    setting_enabled = str(result.get('system_setting_enabled', '0')).strip()
    if setting_enabled == '1':
        score += 30
        feedback.append("System setting 'Active Scheduled Reports' is enabled.")
    else:
        feedback.append("Failed: System setting 'Active Scheduled Reports' is NOT enabled.")

    # Criterion 2: Report Record Exists (20 pts)
    if result.get('report_exists'):
        score += 20
        feedback.append(f"Scheduled report '{target_id}' created.")
        
        report_data = result.get('report_data', {})
        
        # Criterion 3: Correct Report Type (15 pts)
        # Verify it's an export calls report
        actual_report_id = report_data.get('report_id', '')
        if target_report in actual_report_id:
            score += 15
            feedback.append("Correct report type selected.")
        else:
            feedback.append(f"Wrong report type: expected '{target_report}', got '{actual_report_id}'.")

        # Criterion 4: Correct Run Time (15 pts)
        actual_time = str(report_data.get('run_time', ''))
        # Handle potential leading/trailing format diffs, though usually exact
        if target_time in actual_time:
            score += 15
            feedback.append(f"Correct run time ({target_time}).")
        else:
            feedback.append(f"Wrong run time: expected '{target_time}', got '{actual_time}'.")

        # Criterion 5: Correct Email (10 pts)
        actual_email = report_data.get('email_to', '')
        if target_email == actual_email:
            score += 10
            feedback.append("Correct email recipient.")
        else:
            feedback.append(f"Wrong email: expected '{target_email}', got '{actual_email}'.")
            
        # Criterion 6: Description/Notes (5 pts)
        # Allow partial match
        notes = report_data.get('notes', '')
        if "Compliance" in notes or "Daily" in notes:
            score += 5
            feedback.append("Description set correctly.")
        else:
            feedback.append("Description/Notes missing or incorrect.")

    else:
        feedback.append(f"Failed: Scheduled report '{target_id}' was not found in database.")

    # VLM Verification (5 pts)
    # Just to confirm the UI interaction flow if the DB check is borderline or as sanity check
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    if score >= 60: # Only run expensive VLM if likely passing
        vlm_res = query_vlm(
            images=frames + [final_screen],
            prompt="Does the user appear to be configuring a scheduled report or system settings in Vicidial?"
        )
        if vlm_res and vlm_res.get('success', False):
             score += 5
             feedback.append("VLM confirms UI interaction.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }