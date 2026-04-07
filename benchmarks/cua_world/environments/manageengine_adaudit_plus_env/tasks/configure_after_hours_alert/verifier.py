#!/usr/bin/env python3
"""
Verifier for configure_after_hours_alert task in ManageEngine ADAudit Plus.

Verification Strategy:
1.  **VLM Trajectory Analysis (Primary)**:
    - Scans trajectory screenshots to verify the user configuration steps.
    - Checks for:
        a) "Off-Hours_Admin_Activity" name entry.
        b) Selection of "User Management" category.
        c) Selection of "Non-Business Hours" (CRITICAL).
        d) Saving the profile.

2.  **Final State Verification**:
    - Checks if the alert profile appears in the final list screenshot.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_after_hours_alert(traj, env_info, task_info):
    """
    Verifies that the "Off-Hours_Admin_Activity" alert profile was created with correct settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('alert_name', 'Off-Hours_Admin_Activity')
    
    # 1. Retrieve Result JSON from Container
    # Note: Windows path in container needs to be handled. copy_from_env usually handles the mapping
    # but we provided a Windows path in export_result.ps1. 
    # If the env driver maps C:\workspace to a local dir, we might access it directly, 
    # but standard protocol is copy_from_env using the absolute path inside the VM.
    
    # We need to map the Windows path to something copy_from_env understands.
    # Assuming copy_from_env accepts the path as defined in the guest OS.
    guest_result_path = r"C:\workspace\tasks\configure_after_hours_alert\task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(guest_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        # Fail gracefully if file missing, but try VLM anyway
        result_data = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Trajectory Verification
    # We need to find evidence of the specific configuration settings, 
    # especially "Non-Business Hours" which is the core of the task.
    
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}

    prompt = f"""
    You are verifying an IT configuration task in ManageEngine ADAudit Plus.
    The user was supposed to create an alert profile with these specific settings:
    1. Name: "{expected_name}"
    2. Event Category: User Management / Modification
    3. Time Criteria: "Non-Business Hours" (or "During Non-Business Hours")
    4. Severity: Critical

    Review the provided sequence of screenshots.
    
    Step 1: Look for the Alert Profile configuration form.
    Step 2: confirm the Name "{expected_name}" was entered.
    Step 3: Confirm the Time/Business Hours dropdown or setting was set to "Non-Business Hours". THIS IS CRITICAL.
    Step 4: Confirm the profile was saved (e.g., seeing it in the list at the end).

    Output JSON:
    {{
        "form_seen": true/false,
        "correct_name_entered": true/false,
        "non_business_hours_selected": true/false,
        "severity_critical_selected": true/false,
        "profile_saved_successfully": true/false,
        "final_list_shows_profile": true/false,
        "reasoning": "Explain what you saw regarding the Time Criteria"
    }}
    """

    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    if not vlm_response.get('success'):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to run"}

    analysis = vlm_response.get('parsed', {})
    
    # Scoring
    score = 0
    feedback = []

    if analysis.get('correct_name_entered') or analysis.get('final_list_shows_profile'):
        score += 30
        feedback.append(f"Profile '{expected_name}' created.")
    else:
        feedback.append(f"Profile '{expected_name}' not found.")

    if analysis.get('non_business_hours_selected'):
        score += 40
        feedback.append("Correctly configured for Non-Business Hours.")
    else:
        feedback.append("Failed to verify Non-Business Hours setting.")

    if analysis.get('severity_critical_selected'):
        score += 10
        feedback.append("Severity set to Critical.")

    if analysis.get('profile_saved_successfully') or analysis.get('final_list_shows_profile'):
        score += 20
        feedback.append("Profile saved successfully.")
    
    # Check app running status from result.json as a sanity check
    if result_data.get('app_running', False):
        # Good, keep score
        pass
    else:
        # If app wasn't running at end, maybe crashed, penalize slightly?
        # Usually not needed if VLM confirms work was done.
        pass

    passed = score >= 70 and analysis.get('non_business_hours_selected')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": analysis
    }