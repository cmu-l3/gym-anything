#!/usr/bin/env python3
"""
Verifier for add_ems_resource task.
Verifies that the agent added the Metro Lifeline Ambulance Service to CAMEO Data Manager.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_ems_resource(traj, env_info, task_info):
    """
    Verify the agent added the EMS resource correctly.
    
    Strategy:
    1. VLM Trajectory Analysis (Primary): Did agent navigate to Resources -> Add New -> Enter Data?
    2. VLM Final State (Secondary): Is the record visible in the final screenshot?
    3. File/DB Modification (Anti-gaming): Was the database modified during the task?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('resource_name', "Metro Lifeline Ambulance Service")
    
    # 1. Load exported result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    # Criterion 1: Database Modification (15 pts)
    # This prevents "do nothing" agents
    if result_data.get('db_modified', False):
        score += 15
        feedback_parts.append("Database file was modified.")
    else:
        feedback_parts.append("Database file NOT modified (Action not saved?).")
        
    # Criterion 2: VLM Trajectory Verification (45 pts)
    frames = sample_trajectory_frames(traj, n=4)
    traj_prompt = f"""
    Analyze this sequence of screenshots from a user interacting with CAMEO Data Manager.
    Goal: Add a new community resource named "{expected_name}".
    
    Look for these steps:
    1. Navigation to the "Resources" section/module.
    2. Opening a form to add a new record.
    3. Typing "{expected_name}" or "Metro Lifeline" into a name field.
    4. Entering address/phone details (Jefferson City, 573 area code).
    5. Saving the record.
    
    Return JSON:
    {{
        "navigated_resources": true/false,
        "opened_new_record": true/false,
        "entered_name": true/false,
        "entered_details": true/false,
        "saved_record": true/false,
        "confidence": "low/medium/high"
    }}
    """
    
    traj_result = query_vlm(images=frames, prompt=traj_prompt)
    traj_data = traj_result.get('parsed', {})
    
    if traj_data.get('navigated_resources'): score += 10
    if traj_data.get('opened_new_record'): score += 10
    if traj_data.get('entered_name'): score += 15
    if traj_data.get('entered_details'): score += 10
    
    # Criterion 3: Final State Verification (40 pts)
    final_screenshot = get_final_screenshot(traj)
    final_prompt = f"""
    Analyze the final state of the application.
    Does the screen show the record for "{expected_name}"?
    
    Look for:
    - The name "{expected_name}" clearly visible.
    - An indication that this is a saved record (not just a blank form).
    - Category related to EMS/Ambulance.
    
    Return JSON:
    {{
        "record_visible": true/false,
        "correct_name_visible": true/false,
        "category_correct": true/false
    }}
    """
    
    final_result = query_vlm(image=final_screenshot, prompt=final_prompt)
    final_data = final_result.get('parsed', {})
    
    if final_data.get('record_visible'): score += 15
    if final_data.get('correct_name_visible'): score += 20
    if final_data.get('category_correct'): score += 5
    
    # Combine feedback
    if traj_data.get('entered_name'):
        feedback_parts.append("VLM confirmed data entry.")
    else:
        feedback_parts.append("VLM did NOT see data entry.")
        
    if final_data.get('correct_name_visible'):
        feedback_parts.append(f"Final screen shows '{expected_name}'.")
    else:
        feedback_parts.append(f"Final screen does NOT show '{expected_name}'.")

    passed = score >= 70 and result_data.get('db_modified', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }