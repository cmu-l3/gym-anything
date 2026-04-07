#!/usr/bin/env python3
"""
Verifier for set_notch_filter_50hz task.

Criteria:
1. OpenBCI GUI is running (10 pts)
2. Agent took a screenshot as requested (10 pts)
3. VLM Verification (80 pts):
   - Confirms Notch Filter is set to 50 Hz
   - Confirms Session is active (data streaming)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_notch_filter_50hz(traj, env_info, task_info):
    """
    Verify that the Notch filter was set to 50 Hz.
    """
    # 1. Setup and Load JSON result
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env or query_vlm missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Process Status (10 pts)
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("OpenBCI GUI is running.")
    else:
        feedback_parts.append("OpenBCI GUI was closed (failed).")

    # 3. Check User Screenshot (10 pts)
    if result.get('user_screenshot_exists', False) and result.get('user_screenshot_valid_time', False):
        score += 10
        feedback_parts.append("Screenshot taken as requested.")
    else:
        feedback_parts.append("No valid screenshot taken by agent.")

    # 4. VLM Verification (80 pts)
    # Use final screenshot from the system export, or the user's screenshot if the final one is empty?
    # Prefer system final screenshot to verify actual state at end.
    
    final_img = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    if final_img:
        prompt = """
        Analyze this screenshot of the OpenBCI GUI.
        1. Look at the Time Series widget (usually the top/main panel).
        2. Find the "Notch" filter setting button/indicator.
        3. Does it specifically say "50Hz", "50 Hz", or just "50"?
        4. Is the session active? (Are there waveforms visible in the graph, or a 'Stop Session' button visible?)

        Return JSON:
        {
            "notch_is_50hz": boolean,
            "session_active": boolean,
            "reasoning": "string"
        }
        """
        
        vlm_response = query_vlm(images=[final_img], prompt=prompt)
        
        if vlm_response.get('success'):
            analysis = vlm_response.get('parsed', {})
            logger.info(f"VLM Analysis: {analysis}")
            
            # Score Notch Filter (50 pts)
            if analysis.get('notch_is_50hz', False):
                score += 50
                feedback_parts.append("Notch filter verified at 50 Hz.")
            else:
                feedback_parts.append("Notch filter NOT detected at 50 Hz (check VLM reasoning).")
                
            # Score Active Session (30 pts)
            if analysis.get('session_active', False):
                score += 30
                feedback_parts.append("Session appears active.")
            else:
                feedback_parts.append("Session does not appear active.")
                
            feedback_parts.append(f"VLM reasoning: {analysis.get('reasoning', 'None')}")
        else:
            feedback_parts.append("VLM verification failed to run.")
    else:
        feedback_parts.append("No final screenshot available for VLM.")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }