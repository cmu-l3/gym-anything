#!/usr/bin/env python3
"""
Verifier for add_employee_host task in Jolly Lobby Track.

VERIFICATION STRATEGY:
1. Anti-gaming: Check if the application database file was modified during the task.
2. VLM Verification: Analyze the final screenshot and trajectory to confirm:
   - The user navigated to a host/employee list or form.
   - The name "Marcus Chen" was entered.
   - The department "Engineering" was entered.
   - The final state shows the new user in the directory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_employee_host(traj, env_info, task_info):
    """
    Verify that the agent added 'Marcus Chen' to the employee host directory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Signals
    db_modified = result.get('db_modified', False)
    app_running = result.get('app_running', False)
    
    score = 0
    feedback_parts = []
    
    # Signal 1: App Running (10 pts)
    if app_running:
        score += 10
        feedback_parts.append("Application is running.")
    else:
        feedback_parts.append("Application was closed.")

    # Signal 2: Database Modification (30 pts)
    # This is a strong proxy for "saved changes"
    if db_modified:
        score += 30
        feedback_parts.append("Database file modified (saved changes detected).")
    else:
        feedback_parts.append("No database changes detected (did you save?).")

    # 3. VLM Verification (60 pts)
    # We check both the final state and the trajectory
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    
    # Combined prompt for efficiency
    prompt = """
    You are verifying if a user successfully added a new employee host to the 'Lobby Track' software.
    
    Task Details:
    - Name: Marcus Chen
    - Department: Engineering
    
    Review the provided screenshots (trajectory and final state).
    
    Check for the following evidence:
    1. Navigation: Did the user open a "Hosts", "Employees", or "Directory" management screen?
    2. Data Entry: Is there a form visible where "Marcus" and "Chen" were typed?
    3. Success: Does the FINAL screenshot show "Marcus Chen" listed in a table, list, or directory? 
       OR does it show a success message confirming the addition?
    
    Respond in JSON format:
    {
        "navigated_to_hosts": boolean,
        "data_entered_correctly": boolean,
        "final_success_visible": boolean,
        "confidence": "low|medium|high",
        "reasoning": "string"
    }
    """
    
    images_to_check = trajectory_frames + [final_screenshot] if final_screenshot else trajectory_frames
    
    if not images_to_check:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No screenshots available for verification."
        }

    try:
        vlm_response = query_vlm(images=images_to_check, prompt=prompt)
        parsed = vlm_response.get('parsed', {})
        
        navigated = parsed.get('navigated_to_hosts', False)
        data_entered = parsed.get('data_entered_correctly', False)
        success_visible = parsed.get('final_success_visible', False)
        
        # Scoring VLM components
        if navigated:
            score += 10
            feedback_parts.append("Navigated to host management.")
        
        if data_entered:
            score += 20
            feedback_parts.append("Correct data entry observed.")
            
        if success_visible:
            score += 30
            feedback_parts.append("New host visible in directory.")
        elif db_modified and data_entered:
            # Fallback: if we saw them enter data and DB changed, but final screen navigated away
            score += 20 
            feedback_parts.append("Host likely saved (inferred from DB change + entry).")

    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("Visual verification failed due to error.")

    # Pass logic
    # Must have evidence of saving (DB modified OR success visible) AND reasonable score
    passed = (score >= 60) and (db_modified or success_visible)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }