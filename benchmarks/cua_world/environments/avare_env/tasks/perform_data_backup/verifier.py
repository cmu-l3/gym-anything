#!/usr/bin/env python3
"""
Verifier for perform_data_backup task.

Criteria:
1. Valid backup file created (Primary Signal) - 40 pts
   - Must exist
   - Must be created *after* task start
   - Must have non-zero size
2. Navigation/Interaction (Secondary Signal - VLM) - 40 pts
   - VLM confirms "Backup" or "Data I/O" screen was visited
   - VLM confirms success dialog or toast (optional but good)
3. App State (Tertiary Signal) - 20 pts
   - App is running/focused at end

Total: 100 pts
Pass Threshold: 60 pts AND (Backup File Created OR Strong VLM Evidence of completion)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_data_backup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # 1. Retrieve JSON Result from Container
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        # We continue, as VLM might save us if file check failed due to path issues
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Extract Data
    backup_found = result_data.get('backup_found', False)
    backup_size = result_data.get('backup_file_size', 0)
    app_focused = result_data.get('app_focused', False)
    
    score = 0
    feedback = []

    # 3. Score File Evidence
    if backup_found:
        if backup_size > 100:
            score += 40
            feedback.append("Backup file successfully created")
        else:
            score += 20
            feedback.append("Backup file found but size is suspiciously small")
    else:
        feedback.append("No new backup file detected in standard storage locations")

    if app_focused:
        score += 20
        feedback.append("Avare app was focused at end of task")

    # 4. Score VLM Evidence (Trajectory Analysis)
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    # We want to see if they visited the Options/Preferences menu
    vlm_prompt = """
    Analyze these screenshots of the Avare aviation app.
    I am looking for evidence that the user performed a 'Data Backup'.
    
    Look for:
    1. A menu showing 'Options', 'Preferences', or 'Tools'.
    2. A screen titled 'Data I/O', 'Backup', or 'Storage'.
    3. A success message, toast, or dialog saying 'Backup Complete' or 'Saved'.
    4. The user tapping a 'Backup' button.
    
    Return JSON:
    {
        "menu_accessed": true/false,
        "backup_screen_seen": true/false,
        "backup_action_observed": true/false,
        "success_message_seen": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    vlm_score = 0
    if vlm_data.get('backup_screen_seen'):
        vlm_score += 20
        feedback.append("VLM: Backup/Data screen visited")
    if vlm_data.get('backup_action_observed') or vlm_data.get('success_message_seen'):
        vlm_score += 20
        feedback.append("VLM: Backup action or success message observed")
    
    score += vlm_score

    # 5. Final Decision
    # To pass, you generally need the file. 
    # Exception: If file checking failed (wrong path) but VLM is VERY confident (score > 30 from VLM), we might allow a partial pass or lower threshold?
    # Strict rule: File creation is the objective.
    
    passed = False
    if score >= 60:
        if backup_found:
            passed = True
        elif vlm_score >= 35: # High VLM confidence fallback
            passed = True
            feedback.append("Passed based on visual confirmation despite missing file verification")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback),
        "details": {
            "file_check": result_data,
            "vlm_check": vlm_data
        }
    }