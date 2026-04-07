#!/usr/bin/env python3
"""
Verifier for download_terrain_data task in Avare.

Strategy:
1. Filesystem Verification: Check if new terrain data files (>10KB) were created 
   in the Avare data directory during the task window.
2. VLM Verification: Use trajectory frames to confirm the agent:
   - Accessed the Download manager
   - Expanded the Terrain/Elevation category
   - Initiated a download
   - Returned to the Map view
"""

import json
import os
import tempfile
import logging
import time
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_download_terrain_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # =========================================================
    # 1. Retrieve Data from Container
    # =========================================================
    temp_dir = tempfile.mkdtemp()
    try:
        # Copy main result JSON
        local_result_json = os.path.join(temp_dir, "task_result.json")
        copy_from_env("/sdcard/task_result.json", local_result_json)
        
        with open(local_result_json, 'r') as f:
            result_data = json.load(f)
            
        # Copy the file list JSON created by the shell script
        local_files_json = os.path.join(temp_dir, "found_files.json")
        copy_from_env(result_data.get("found_files_json_path"), local_files_json)
        
        with open(local_files_json, 'r') as f:
            found_files = json.load(f)
            
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task data: {str(e)}. Did the agent run the export script?"
        }

    # =========================================================
    # 2. Filesystem Verification (40 points)
    # =========================================================
    task_start = int(result_data.get("task_start_time", 0))
    min_size = task_info.get("metadata", {}).get("min_file_size_bytes", 10240)
    
    valid_new_files = []
    for f in found_files:
        # Check timestamp (created/modified after task start)
        # Allow small buffer (e.g., 5s) for clock skew
        if f['mtime'] > (task_start - 5):
            # Check size
            if f['size'] > min_size:
                valid_new_files.append(f)

    fs_score = 0
    feedback_parts = []
    
    if len(valid_new_files) > 0:
        fs_score = 40
        feedback_parts.append(f"SUCCESS: {len(valid_new_files)} new terrain data files downloaded.")
        for vf in valid_new_files[:2]:
            logger.info(f"Validated file: {vf['path']} ({vf['size']} bytes)")
    else:
        feedback_parts.append("FAIL: No valid new terrain files found on filesystem.")
        if len(found_files) > 0:
            feedback_parts.append(f"(Found {len(found_files)} potential files, but they were either old or too small)")

    # =========================================================
    # 3. VLM Verification (60 points)
    # =========================================================
    # We need to verify the workflow using trajectory frames
    frames = sample_trajectory_frames(traj, n=8)
    final_screen = get_final_screenshot(traj)
    
    # Prompt designed to check specific workflow steps
    vlm_prompt = """
    You are verifying an agent using the Avare aviation GPS app. The task is to download terrain/elevation data.
    
    Review the sequence of screenshots and verify these steps:
    1. Did the agent open the 'Download' or 'Map Data' manager screen? (Look for a list of categories like Databases, Maps, Charts)
    2. Did the agent expand a 'Terrain', 'Elevation', or 'CONUS' category? (Look for an indented list of regions/tiles)
    3. Did the agent select a region and press 'Get' or 'Download'?
    4. Did the agent return to the main Map view at the end?
    
    Return a JSON object with:
    {
        "download_menu_accessed": true/false,
        "terrain_category_expanded": true/false,
        "download_initiated": true/false,
        "returned_to_map": true/false,
        "reasoning": "your observations"
    }
    """
    
    vlm_result = query_vlm(
        prompt=vlm_prompt,
        images=frames + [final_screen]
    )
    
    vlm_score = 0
    vlm_data = vlm_result.get("parsed", {})
    
    if vlm_data.get("download_menu_accessed"):
        vlm_score += 15
        feedback_parts.append("VLM: Download menu accessed.")
    
    if vlm_data.get("terrain_category_expanded"):
        vlm_score += 15
        feedback_parts.append("VLM: Terrain category expanded.")
        
    if vlm_data.get("download_initiated"):
        vlm_score += 20
        feedback_parts.append("VLM: Download initiated.")
        
    if vlm_data.get("returned_to_map"):
        vlm_score += 10
        feedback_parts.append("VLM: Returned to map view.")
        
    feedback_parts.append(f"VLM Analysis: {vlm_data.get('reasoning', 'No reasoning provided')}")

    # =========================================================
    # 4. Final Scoring
    # =========================================================
    total_score = fs_score + vlm_score
    
    # Anti-gaming / Sanity check
    # If file system shows success but VLM saw nothing, suspicious.
    # If VLM saw success but files missing, maybe download failed/timeout.
    
    passed = False
    if total_score >= 60:
        # Require at least some evidence of download (either file or VLM confirmation of action)
        if len(valid_new_files) > 0 or vlm_data.get("download_initiated"):
            passed = True
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }