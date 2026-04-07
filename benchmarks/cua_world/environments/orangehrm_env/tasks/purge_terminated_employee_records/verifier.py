#!/usr/bin/env python3
"""
Verifier for purge_terminated_employee_records task.

CRITERIA:
1. Target employee 'David Obsolete' must be purged (Count = 0).
2. Control employee 'David Current' must remain (Count = 1).
3. VLM verification of the workflow (Maintenance module access).
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_purge_terminated_employee_records(traj, env_info, task_info):
    """
    Verify that the specific employee record was purged while preserving others.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Load Result JSON
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

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Database State
    target_count = result.get('final_target_count', 1)
    control_count = result.get('final_control_count', 0)
    
    # Criterion 1: Target Gone (70 pts)
    if target_count == 0:
        score += 70
        feedback_parts.append("Target employee 'David Obsolete' successfully purged.")
    else:
        feedback_parts.append("Target employee 'David Obsolete' still exists in database.")

    # Criterion 2: Control Safe (20 pts)
    if control_count >= 1:
        score += 20
        feedback_parts.append("Control employee 'David Current' remains safe.")
    else:
        feedback_parts.append("WARNING: Control employee 'David Current' was accidentally purged!")

    # 3. VLM Verification (10 pts)
    # Check if agent accessed Maintenance module using trajectory frames
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        # We look for "Maintenance" header or Purge confirmation screens
        prompt = """
        Review these screenshots of an agent using OrangeHRM.
        Did the agent:
        1. Navigate to the 'Maintenance' module?
        2. Access 'Purge Employee Records'?
        3. Show a search or confirmation screen for purging records?
        
        Answer with JSON: {"maintenance_accessed": bool, "purge_screen_visible": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("maintenance_accessed") or parsed.get("purge_screen_visible"):
                    vlm_score = 10
                    feedback_parts.append("Visual evidence of Maintenance module usage confirmed.")
                else:
                    feedback_parts.append("No visual evidence of Maintenance module usage.")
            else:
                # Fallback if VLM fails but app was running
                if result.get("app_was_running"):
                    vlm_score = 5
                    feedback_parts.append("App was running (VLM check failed).")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if result.get("app_was_running"):
                vlm_score = 5
    
    score += vlm_score

    passed = (score >= 90) # Requires Target Gone + Control Safe
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }