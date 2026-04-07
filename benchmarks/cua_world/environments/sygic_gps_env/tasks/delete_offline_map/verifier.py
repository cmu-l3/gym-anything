#!/usr/bin/env python3
"""
Verifier for delete_offline_map task.

Task: Delete the 'American Samoa' offline map.

Verification Strategy:
1. Programmatic: Check if map files are removed from the device.
2. Programmatic: Check if storage usage decreased.
3. VLM: Analyze trajectory to verify the agent navigated the menu and clicked delete.
4. VLM: Verify final screen does not show the map as installed.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_offline_map(traj, env_info, task_info):
    """
    Verifies that the American Samoa map was deleted.
    """
    # 1. Setup and copy results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_log = []
    
    # =========================================================
    # CRITERION 1: Filesystem Check (Primary Programmatic) - 40 pts
    # =========================================================
    map_exists = result_data.get('map_files_exist', True)
    initial_count = int(result_data.get('initial_file_count', 0))
    final_count = int(result_data.get('final_file_count', 0))

    files_removed = False
    if initial_count > 0 and final_count == 0:
        files_removed = True
        score += 40
        feedback_log.append("SUCCESS: Map files were removed from device storage.")
    elif initial_count > 0 and final_count < initial_count:
        # Partial removal?
        score += 20
        feedback_log.append("PARTIAL: Some map files removed, but traces remain.")
    elif initial_count == 0:
        feedback_log.append("WARNING: Map files were missing at start. Verification relies on VLM.")
    else:
        feedback_log.append("FAIL: Map files still exist on device.")

    # =========================================================
    # CRITERION 2: Storage Check (Secondary Programmatic) - 10 pts
    # =========================================================
    init_storage = int(result_data.get('initial_storage_kb', 0))
    final_storage = int(result_data.get('final_storage_kb', 0))
    
    if init_storage > final_storage:
        score += 10
        feedback_log.append(f"SUCCESS: Storage usage decreased ({init_storage}kb -> {final_storage}kb).")
    elif init_storage == final_storage:
        feedback_log.append("INFO: Storage usage unchanged.")
    else:
        feedback_log.append("INFO: Storage usage increased (unexpected).")

    # =========================================================
    # CRITERION 3: VLM Trajectory Verification - 50 pts
    # =========================================================
    # We need to confirm the agent actually did this in the UI, not just `rm` command
    
    frames = sample_trajectory_frames(traj, n=5)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
        feedback_log.append("FAIL: No screenshots available for verification.")
    else:
        # Prompt designed to check workflow and final state
        prompt = """
        You are verifying a task in Sygic GPS Navigation app.
        The goal is: "Delete the 'American Samoa' offline map".

        Analyze the provided sequence of screenshots (trajectory) and the final screenshot.
        
        Check for these specific steps:
        1. Did the user open the Main Menu?
        2. Did the user navigate to "Offline Maps" (or Maps Management)?
        3. Did the user select/find "American Samoa" in the list?
        4. Did the user click a "Delete" (trash bin) icon or "Remove" button?
        5. In the FINAL screenshot, is "American Samoa" GONE from the downloaded list (or shown as not installed)?

        Return a JSON object:
        {
            "menu_opened": true/false,
            "offline_maps_accessed": true/false,
            "target_map_seen": true/false,
            "delete_action_observed": true/false,
            "final_state_correct": true/false,
            "explanation": "Brief reasoning"
        }
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_shot], prompt=prompt)
            vlm_data = vlm_response.get('parsed', {})
            
            # Score workflow
            if vlm_data.get('menu_opened'): score += 5
            if vlm_data.get('offline_maps_accessed'): score += 10
            if vlm_data.get('target_map_seen'): score += 5
            
            # Score action (Critical)
            if vlm_data.get('delete_action_observed'): 
                score += 15
                feedback_log.append("VLM: Deletion action observed.")
            else:
                feedback_log.append("VLM: Deletion action NOT clearly observed.")

            # Score final state (Critical)
            if vlm_data.get('final_state_correct'): 
                score += 15
                feedback_log.append("VLM: Final screen confirms map is gone.")
            else:
                feedback_log.append("VLM: Map still appears visible/installed in final screen.")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_log.append(f"VLM verification error: {str(e)}")

    # =========================================================
    # Final Verdict
    # =========================================================
    passed = score >= 60 and (files_removed or score >= 70) 
    # Must remove files OR have very convincing visual evidence (in case file path logic is flaky)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_log)
    }