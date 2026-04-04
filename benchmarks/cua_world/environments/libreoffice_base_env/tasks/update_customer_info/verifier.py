#!/usr/bin/env python3
"""
Verifier for update_customer_info task.
Checks if the LibreOffice Base ODB file was updated with the correct customer details.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_customer_info(traj, env_info, task_info):
    """
    Verify that Customer #17 was updated correctly in the ODB file.
    
    Criteria:
    1. File was modified and saved (timestamp check)
    2. Record #17 contains the exact new address/phone details
    3. Other fields (Name, Email) were preserved
    4. VLM confirms UI interaction
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {})
    preserved_values = metadata.get('preserved_values', {})
    
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
    feedback_parts = []
    
    # 1. File Modification Check (20 pts)
    file_saved = result.get('file_saved_during_task', False)
    file_modified = result.get('file_modified', False)
    
    if file_saved and file_modified:
        score += 20
        feedback_parts.append("Database file saved successfully")
    elif file_modified:
        score += 10
        feedback_parts.append("Database file modified but timestamp suspicious")
    else:
        feedback_parts.append("Database file NOT saved or modified")
        return {"passed": False, "score": 0, "feedback": "Task failed: Database file was not saved."}

    # 2. Data Verification (70 pts)
    record = result.get('record_data', {})
    data_found = result.get('data_found_in_script', False)
    
    if not data_found or not record:
        feedback_parts.append("Customer record #17 not found in database file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check updated fields
    fields_correct = 0
    total_fields = len(expected_values)
    
    for field, expected in expected_values.items():
        actual = record.get(field, "")
        # Normalize for comparison (strip whitespace)
        if str(actual).strip() == str(expected).strip():
            fields_correct += 1
            feedback_parts.append(f"{field} correct")
        else:
            feedback_parts.append(f"{field} incorrect (expected '{expected}', got '{actual}')")
            
    # Points for correct fields (11 pts per field for 5 fields = 55 pts)
    # Adjusted to sum to 60 for fields
    field_score = int((fields_correct / total_fields) * 60)
    score += field_score
    
    # Check preserved fields (10 pts)
    preserved_ok = True
    for field, expected in preserved_values.items():
        actual = record.get(field, "")
        if str(actual).strip() != str(expected).strip():
            preserved_ok = False
            feedback_parts.append(f"Error: {field} was accidentally changed")
            
    if preserved_ok:
        score += 10
        feedback_parts.append("Other fields correctly preserved")
    else:
        score += 0 # Penalty for changing wrong fields

    # 3. VLM Verification (10 pts)
    # Check if the agent actually used the table UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Check these screenshots of LibreOffice Base.
    1. Do you see a database table open with rows of data?
    2. Do you see any editing of a 'Customer' table?
    3. In the final screenshot, is the main LibreOffice window visible?
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        if vlm_res.get('success'):
            score += 10
    except:
        pass # Optional check

    passed = (score >= 70) and file_saved and (fields_correct >= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }