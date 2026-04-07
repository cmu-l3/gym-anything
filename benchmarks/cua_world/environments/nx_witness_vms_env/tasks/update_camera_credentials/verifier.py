#!/usr/bin/env python3
"""
Verifier for update_camera_credentials task.
Checks:
1. API state: Do the cameras have the correct updated usernames?
2. Log file: Does it exist, was it created during the task, and does it have the correct format?
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_camera_credentials(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define targets from metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [
        {"name": "Parking Lot Camera", "expected_user": "cam_admin"},
        {"name": "Entrance Camera", "expected_user": "cam_operator"},
        {"name": "Server Room Camera", "expected_user": "srv_monitor"}
    ])
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Data from result
    task_start = result.get('task_start', 0)
    camera_states = result.get('camera_states', [])
    log_exists = result.get('log_file_exists', False)
    log_mtime = result.get('log_file_mtime', 0)
    log_content = result.get('log_content', "")

    # ==========================================
    # 1. API State Verification (60 points)
    # ==========================================
    # Map current states by name
    current_map = {cam.get('name'): cam.get('user') for cam in camera_states}
    
    cameras_correct = 0
    for target in targets:
        name = target['name']
        expected = target['expected_user']
        actual = current_map.get(name)
        
        if actual == expected:
            cameras_correct += 1
            score += 20
            feedback_parts.append(f"✅ {name} updated correctly.")
        else:
            feedback_parts.append(f"❌ {name}: expected '{expected}', found '{actual}'.")

    # ==========================================
    # 2. Log File Verification (40 points)
    # ==========================================
    if log_exists:
        # Check creation time anti-gaming
        if log_mtime > task_start:
            score += 10
            feedback_parts.append("✅ Log file created/modified during task.")
            
            # Check content
            # Expecting 3 lines, each mentioning a camera and username
            log_lines = log_content.strip().split('\n')
            
            valid_entries = 0
            for target in targets:
                target_name = target['name']
                target_user = target['expected_user']
                
                # Check if any line contains both name and user
                found_entry = False
                for line in log_lines:
                    if target_name in line and target_user in line:
                        # Rudimentary format check: check for timestamp brackets and ID
                        if '[' in line and ']' in line and 'ID:' in line:
                            found_entry = True
                            break
                
                if found_entry:
                    valid_entries += 1
            
            if valid_entries == 3:
                score += 30
                feedback_parts.append("✅ Log file contains correct entries for all cameras.")
            elif valid_entries > 0:
                score += (valid_entries * 10)
                feedback_parts.append(f"⚠️ Log file contains {valid_entries}/3 correct entries.")
            else:
                feedback_parts.append("❌ Log file content format incorrect or missing data.")
                
        else:
            feedback_parts.append("❌ Log file detected but timestamp predates task (stale file).")
    else:
        feedback_parts.append("❌ Log file not found.")

    # ==========================================
    # Final Scoring
    # ==========================================
    passed = (score >= 60) and log_exists and (cameras_correct >= 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }