#!/usr/bin/env python3
"""
Verifier for configure_discovery_exclusion task.

Verification Strategy:
1. Primary: VLM Trajectory Analysis
   - Verify the agent navigated to Admin > Discovery/Scan settings.
   - Verify the specific IP '192.168.100.50' was entered into an exclusion list.
   - Verify the 'Save' action was taken.
2. Secondary: System State
   - Verify the browser was running (via export script).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_discovery_exclusion(traj, env_info, task_info):
    """
    Verifies that the agent added the specific IP to the exclusion list.
    """
    # 1. Setup and basic checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Retrieve exported result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: The export script saves to C:\workspace\tasks\task_result.json
        # We need to map that to the container path. 
        # Assuming the standard path provided in export_result.ps1
        copy_from_env("C:\\workspace\\tasks\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task result file: {e}")
        task_result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not frames and not final_frame:
        return {"passed": False, "score": 0, "feedback": "No video evidence available."}

    # Include final frame in analysis
    analysis_frames = frames + [final_frame] if final_frame else frames

    prompt = """
    You are evaluating an IT administrator task. 
    The goal is to add the IP address '192.168.100.50' to the "Exclude IP", "Scan Exclusion", or "Network Discovery" exclusion list in ManageEngine ADAudit Plus.

    Review the screenshots provided.
    
    Check for the following:
    1. **Navigation**: Did the user navigate to the Admin/Configuration section for Discovery or Domain Settings?
    2. **Input**: Is the IP address '192.168.100.50' visible in an input field or a list specifically related to 'Exclusion' or 'Exclude'?
    3. **Save**: Did the user click a 'Save' button or is there a success message?
    4. **Final State**: In the final state, is '192.168.100.50' listed as a configured exclusion?

    Output JSON:
    {
        "navigated_to_settings": boolean,
        "ip_entered_correctly": boolean,
        "saved_successfully": boolean,
        "ip_visible_in_list": boolean,
        "confidence": float (0.0 to 1.0),
        "explanation": "string"
    }
    """

    vlm_response = query_vlm(images=analysis_frames, prompt=prompt)
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to process images."}

    try:
        data = vlm_response.get("parsed", {})
        
        score = 0
        feedback_items = []

        # Scoring Logic
        if data.get("navigated_to_settings"):
            score += 30
            feedback_items.append("Correctly navigated to settings.")
        
        if data.get("ip_entered_correctly"):
            score += 40
            feedback_items.append("Entered correct IP (192.168.100.50).")
        else:
            feedback_items.append("Did not detect entry of the correct IP.")

        if data.get("saved_successfully") or data.get("ip_visible_in_list"):
            score += 30
            feedback_items.append("Configuration saved/confirmed.")

        # Browser check (Bonus/Sanity)
        if task_result.get("app_was_running"):
            # Ensure they didn't just close the app immediately
            pass 
        else:
            score = 0
            feedback_items.append("Browser was closed before task completion.")

        passed = score >= 70 and data.get("ip_entered_correctly")

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_items) + f" (VLM Explanation: {data.get('explanation')})"
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing VLM response: {e}"}