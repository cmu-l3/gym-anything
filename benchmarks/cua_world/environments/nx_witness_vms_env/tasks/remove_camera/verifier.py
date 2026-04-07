#!/usr/bin/env python3
"""
Verifier for remove_camera task.
Checks if the specific camera was removed via API and if the audit log was created correctly.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_camera(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Extract data
    initial_count = result.get('initial_camera_count', 0)
    current_count = result.get('current_camera_count', 0)
    target_id = result.get('target_id', '')
    id_still_exists = result.get('id_still_exists', True)
    name_still_exists = result.get('name_still_exists', True)
    
    audit_exists = result.get('audit_file_exists', False)
    audit_fresh = result.get('audit_file_created_during_task', False)
    audit_content = result.get('audit_file_content', '')

    score = 0
    feedback = []

    # Criterion 1: Camera count reduced (20 pts)
    # We expect count to go down by at least 1.
    if current_count < initial_count:
        score += 20
        feedback.append("Camera count reduced.")
    else:
        feedback.append(f"Camera count did not decrease (Initial: {initial_count}, Current: {current_count}).")

    # Criterion 2: Target ID Gone (20 pts)
    if not id_still_exists:
        score += 20
        feedback.append("Target Device ID is gone from system.")
    else:
        feedback.append("Target Device ID still exists in system.")

    # Criterion 3: Target Name Gone (15 pts)
    if not name_still_exists:
        score += 15
        feedback.append("Camera name 'Server Room Camera' is gone.")
    else:
        feedback.append("Camera named 'Server Room Camera' still found.")

    # Criterion 4: Audit File Exists & Fresh (15 pts)
    if audit_exists and audit_fresh:
        score += 15
        feedback.append("Audit file created during task.")
    elif audit_exists:
        score += 5
        feedback.append("Audit file exists but timestamp is old.")
    else:
        feedback.append("Audit file not found.")

    # Criterion 5: Audit File Content (20 pts)
    # Must contain the ID. Name check is bonus/robustness.
    content_score = 0
    if audit_exists:
        if target_id and target_id in audit_content:
            content_score += 15
            feedback.append("Audit file contains correct Device ID.")
        
        if "Server Room" in audit_content or "Server Room Camera" in audit_content:
            content_score += 5
            feedback.append("Audit file contains camera name.")
            
    score += content_score

    # Criterion 6: VLM Verification (10 pts)
    # Check if agent actually interacted with UI/Settings
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        if final_shot:
            frames.append(final_shot)
        
        if frames:
            prompt = """
            Review these screenshots of a user interacting with Nx Witness VMS.
            Did the user:
            1. View camera details or settings?
            2. Open a text editor or file to write down information?
            3. Perform a deletion or removal action?
            
            Return 'YES' if at least one of these actions is visible.
            """
            try:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                if "YES" in vlm_resp.get('response', '').upper():
                    vlm_score = 10
                    feedback.append("VLM confirms UI interaction.")
                else:
                    # Soft fail, maybe they used API entirely
                    feedback.append("VLM did not detect clear UI interaction.")
            except:
                pass
    
    score += vlm_score

    # Pass Condition
    # Must have removed the camera (ID gone) AND created the audit file with ID
    camera_removed = (not id_still_exists)
    audit_valid = (audit_exists and target_id in audit_content)
    
    passed = camera_removed and audit_valid and score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }