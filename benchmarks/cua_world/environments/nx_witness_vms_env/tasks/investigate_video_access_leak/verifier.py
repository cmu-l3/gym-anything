#!/usr/bin/env python3
"""
Verifier for investigate_video_access_leak task.

Verifies that:
1. The agent created the report file.
2. The report file identifies the correct suspect username.
3. The file was created during the task window.
4. Uses VLM to check if the agent actually used the Audit Trail interface.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investigate_video_access_leak(traj, env_info, task_info):
    """
    Verify the investigation result.
    """
    # 1. Setup Interface
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Data
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').lower().strip()
    actual_suspect = result.get('actual_suspect', '').lower().strip()
    file_created_during_task = result.get('file_created_during_task', False)
    
    score = 0
    feedback_parts = []
    
    # 4. Primary Verification: Report Accuracy
    if not report_exists:
        feedback_parts.append("Report file 'leak_report.txt' was not found.")
    else:
        score += 20
        feedback_parts.append("Report file exists.")
        
        if not file_created_during_task:
            feedback_parts.append("Warning: Report file timestamp indicates it wasn't modified during task.")
        else:
            score += 10
            feedback_parts.append("Report file created during task.")

        if report_content == actual_suspect:
            score += 50
            feedback_parts.append(f"Correct suspect identified: '{report_content}'.")
        else:
            feedback_parts.append(f"Incorrect suspect. Reported: '{report_content}', Actual: '{actual_suspect}'.")

    # 5. Secondary Verification: VLM Trajectory Check (Did they use the Audit Trail?)
    # We look for keywords like "Audit", "Log", "System Administration" in screenshots
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Check these screenshots of the Nx Witness VMS interface.
    Does the user navigate to an "Audit Trail", "Logs", or "System Administration" page?
    Do you see a list of events or logs (e.g., login, viewing, access)?
    
    Respond with JSON: {"audit_trail_accessed": true/false, "reasoning": "..."}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    audit_accessed = False
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        audit_accessed = parsed.get('audit_trail_accessed', False)
        if audit_accessed:
            score += 20
            feedback_parts.append("Verified agent accessed Audit/Log interface.")
        else:
            feedback_parts.append("Could not verify visual access to Audit Trail (VLM check).")
    else:
        # If VLM fails, we don't penalize too heavily if the answer was correct, 
        # but we can't award the full process points.
        feedback_parts.append("VLM verification skipped/failed.")
        # Grace points if the answer was correct (implies they must have looked)
        if report_content == actual_suspect and report_content != "":
            score += 20

    # 6. Final Decision
    passed = (score >= 90)  # Requires file exist + correct answer + (process or perfect output)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }