#!/usr/bin/env python3
"""
Verifier for download_vitaldb_case task.

Multi-Criteria Verification:
1. File Existence & Properties (40 pts)
   - Checks if file exists, size > 1MB, and created during task.
2. VLM Trajectory Verification (40 pts)
   - Checks if agent interacted with VitalDB browser (Search, List, Download).
3. Application State (20 pts)
   - Checks if Vital Recorder was running at end.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_download_vitaldb_case(traj, env_info, task_info):
    """
    Verify that the agent downloaded the VitalDB case using the browser.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 1048576) # 1MB default

    score = 0
    feedback_parts = []
    
    # 2. Retrieve JSON Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path inside container/VM mapped to C:\workspace\task_result.json
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring - File Check (40 pts)
    output_exists = result.get('output_exists', False)
    file_size = result.get('output_size_bytes', 0)
    created_during_task = result.get('file_created_during_task', False)

    if output_exists:
        if file_size >= min_size:
            if created_during_task:
                score += 40
                feedback_parts.append("✅ Valid file downloaded during task")
            else:
                score += 20
                feedback_parts.append("⚠️ File exists but timestamp predates task (did you overwrite?)")
        else:
            score += 10
            feedback_parts.append(f"❌ File exists but too small ({file_size} bytes)")
    else:
        feedback_parts.append("❌ Target file not found")

    # 4. Scoring - App State (20 pts)
    if result.get('app_was_running', False):
        score += 20
        feedback_parts.append("✅ Vital Recorder is running")
    else:
        feedback_parts.append("⚠️ Vital Recorder was closed")

    # 5. Scoring - VLM Verification (40 pts)
    # We sample frames to verify the workflow: Opening browser -> Searching/Selecting -> Downloading
    frames = sample_trajectory_frames(traj, n=5)
    
    if not frames:
        feedback_parts.append("⚠️ No trajectory frames available for visual verification")
    else:
        prompt = """
        You are verifying a task in 'Vital Recorder'. The user should have:
        1. Opened the 'VitalDB' case browser/window.
        2. Selected a case (Case 1).
        3. Initiated a download.
        
        Look at these screenshots of the user's actions.
        - Do you see a window titled 'VitalDB' or a list of medical cases?
        - Do you see a download progress bar or dialog?
        - Is the main application showing physiological signal tracks at the end?
        
        Answer JSON: {"vitaldb_browser_seen": bool, "download_activity_seen": bool, "confidence": float}
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_response.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('vitaldb_browser_seen'):
                vlm_score += 20
                feedback_parts.append("✅ VitalDB browser interaction detected")
            if parsed.get('download_activity_seen'):
                vlm_score += 20
                feedback_parts.append("✅ Download activity detected")
            
            score += vlm_score
            
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("⚠️ Visual verification failed due to error")
            # Grant partial credit if file is perfect to avoid penalizing technical hiccups
            if score >= 60: 
                score += 10 

    # 6. Final Determination
    # Must have the file AND reasonable evidence of work
    passed = (score >= 70) and output_exists and (file_size >= min_size)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }