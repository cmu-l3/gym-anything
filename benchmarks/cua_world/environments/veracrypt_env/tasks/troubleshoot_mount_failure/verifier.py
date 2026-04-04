#!/usr/bin/env python3
"""
Verifier for troubleshoot_mount_failure task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_troubleshoot_mount_failure(traj, env_info, task_info):
    """
    Verify the agent successfully diagnosed the missing keyfile, mounted the volume,
    and documented the findings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keyfile_path = metadata.get('hidden_keyfile_path', '/opt/backups/old_keys/project.key')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Volume Mounted (30 pts)
    if result.get('volume_mounted'):
        score += 30
        feedback_parts.append("Volume successfully mounted")
    else:
        feedback_parts.append("Volume NOT mounted")

    # 2. Correct Mount Point (10 pts)
    if result.get('correct_mount_point'):
        score += 10
        feedback_parts.append("Mounted at correct path")
    elif result.get('volume_mounted'):
        feedback_parts.append("Mounted at WRONG path (expected /home/ga/MountPoints/slot2)")

    # 3. Files Accessible (20 pts)
    file_count = result.get('accessible_file_count', 0)
    if result.get('files_accessible') and file_count >= 3:
        score += 20
        feedback_parts.append(f"All {file_count} files accessible")
    elif result.get('files_accessible'):
        score += 10
        feedback_parts.append(f"Some files accessible ({file_count}/3)")
    else:
        feedback_parts.append("Files NOT accessible")

    # 4. Report Exists & Valid (15 pts)
    report_content = result.get('report_content_preview', '')
    if result.get('report_exists') and result.get('report_timestamp_valid'):
        score += 15
        feedback_parts.append("Report created")
    elif result.get('report_exists'):
        feedback_parts.append("Report exists but pre-dates task (anti-gaming fail)")
    else:
        feedback_parts.append("Report MISSING")

    # 5. Keyfile Path in Report (15 pts)
    # Check if the report mentions the location or the keyfile name in the correct context
    if expected_keyfile_path in report_content or "/opt/backups" in report_content:
        score += 15
        feedback_parts.append("Report correctly identifies keyfile location")
    elif "project.key" in report_content:
        score += 5
        feedback_parts.append("Report mentions keyfile but location unclear")
    else:
        feedback_parts.append("Report missing keyfile location info")

    # 6. File Listing in Report (10 pts)
    # Check if filenames appear in report
    files_mentioned = 0
    if "SF312" in report_content: files_mentioned += 1
    if "Revenue" in report_content: files_mentioned += 1
    if "project_plan" in report_content: files_mentioned += 1
    
    if files_mentioned >= 2:
        score += 10
        feedback_parts.append("Report lists volume contents")
    elif files_mentioned == 1:
        score += 5
        feedback_parts.append("Report partially lists contents")

    # VLM Verification (Trajectory check)
    # We want to see evidence of investigation or the mount process
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a troubleshooting task.
        The user is trying to find a missing VeraCrypt keyfile and mount a volume.
        
        Look for:
        1. Terminal windows showing 'ls', 'find', or 'cat' commands (investigation).
        2. Text editors opening log files or notes.
        3. The VeraCrypt window showing a mounted volume.
        4. A report file being edited.
        
        Did the agent perform troubleshooting steps?
        """
        
        if env_info.get('query_vlm'):
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res.get('success'):
                # We mainly use VLM for qualitative feedback in logs, 
                # but could use it to boost score if program check is borderline.
                # Here we just log it to feedback.
                feedback_parts.append(f"VLM: {vlm_res.get('parsed', {}).get('answer', 'Analyzed')}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Pass Threshold
    # Must have mounted the volume AND created a valid report
    passed = (score >= 60) and result.get('volume_mounted') and result.get('report_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }