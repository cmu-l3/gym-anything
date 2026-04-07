#!/usr/bin/env python3
"""
Verifier for configure_restricted_subnet_alert task.

Verification Strategy:
1. VLM Analysis of Trajectory (Primary):
   - Confirms the agent navigated to Alert Profiles.
   - Confirms the specific profile 'WiFi_DC_Logon_Violation' was created.
   - Verifies the 'Client IP Starts With 192.168.50' condition is visible.
2. Artifact Check (Secondary):
   - Checks if task_result.json was generated.
   - Checks if final screenshot exists.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_restricted_subnet_alert(traj, env_info, task_info):
    """
    Verifies that the restricted subnet alert was configured correctly.
    """
    # 1. Setup & Artifact Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('alert_name', 'WiFi_DC_Logon_Violation')
    expected_subnet = metadata.get('target_subnet', '192.168.50')

    score = 0
    feedback = []
    
    # Retrieve result JSON from the Windows environment
    # Note: The path inside container is C:\workspace\task_result.json
    # The 'copy_from_env' usually maps the container path logic. 
    # For Windows containers, paths might need handling. Assuming standard mapping.
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            if result_data.get('screenshot_exists'):
                score += 10
                feedback.append("Final state captured.")
    except Exception as e:
        logger.warning(f"Could not retrieve task_result.json: {e}")
        feedback.append("Warning: Could not retrieve internal task metrics.")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. VLM Verification (Crucial for UI Configuration Tasks)
    # We sample frames to catch the configuration steps
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
        return {"passed": False, "score": score, "feedback": "No visual evidence (screenshots) available."}

    # Prompt designed to verify specific configuration details
    prompt = f"""
    You are verifying an IT configuration task in ManageEngine ADAudit Plus.
    
    The agent was supposed to:
    1. Create a new Alert Profile named '{expected_name}'.
    2. Set the Severity to Critical.
    3. Configure a filter for 'Client IP Address' starting with '{expected_subnet}'.
    
    Examine the screenshots (especially the later ones showing the configuration summary or list).
    
    Question 1: Is the Alert Profile name '{expected_name}' visible?
    Question 2: Is the condition/filter 'Client IP Address' ... '{expected_subnet}' visible?
    Question 3: Is the Severity set to 'Critical'?
    Question 4: Was the profile saved (e.g., seen in the profile list after saving)?
    
    Return JSON:
    {{
        "profile_name_correct": boolean,
        "ip_filter_correct": boolean,
        "severity_correct": boolean,
        "saved_successfully": boolean,
        "reasoning": "string"
    }}
    """
    
    vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_response and vlm_response.get('success'):
        parsed = vlm_response.get('parsed', {})
        
        if parsed.get('profile_name_correct'):
            score += 30
            feedback.append(f"Correct Profile Name '{expected_name}' verified.")
        else:
            feedback.append(f"Could not verify Profile Name '{expected_name}'.")
            
        if parsed.get('ip_filter_correct'):
            score += 30
            feedback.append(f"Correct IP Filter '{expected_subnet}' verified.")
        else:
            feedback.append("Could not verify IP Filter configuration.")
            
        if parsed.get('severity_correct'):
            score += 15
            feedback.append("Severity 'Critical' verified.")
            
        if parsed.get('saved_successfully'):
            score += 15
            feedback.append("Profile saved successfully.")
    else:
        feedback.append("VLM verification failed to process images.")

    # 3. Final Scoring
    # Max Score: 10 (Artifacts) + 30 (Name) + 30 (IP) + 15 (Severity) + 15 (Saved) = 100
    passed = score >= 70 and parsed.get('ip_filter_correct', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }