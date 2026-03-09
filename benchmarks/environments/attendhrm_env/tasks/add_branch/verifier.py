#!/usr/bin/env python3
"""
Verifier for add_branch task (AttendHRM).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_branch(traj, env_info, task_info):
    """
    Verifies that the "Downtown Office" branch was added correctly.
    
    Strategy:
    1. Check programmatic results from the VM (DB query result).
    2. Check VLM trajectory for UI interaction evidence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path inside VM is mapped to C:\tmp\task_result.json
        # But copy_from_env usually expects linux-style path or handles the conversion if the agent is in docker.
        # Since this is a Windows VM, the path mapping depends on the env driver.
        # Assuming the env driver handles "C:\tmp\..." or "/tmp/..." mapping.
        # Often Windows envs map /tmp in the guest to C:\tmp.
        try:
            copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        except:
            # Fallback for some drivers that expect forward slashes
            copy_from_env("/tmp/task_result.json", temp_file.name)
            
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        # Proceed to VLM verification if file missing
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback = []

    # Criteria A: Database Evidence (50 points)
    if task_result.get("record_found"):
        score += 25
        feedback.append("Database: Branch record found.")
    else:
        feedback.append("Database: Branch record NOT found.")

    if task_result.get("code_match"):
        score += 10
        feedback.append("Database: Branch code matches.")
    
    if task_result.get("city_match"):
        score += 5
        feedback.append("Database: City matches.")
        
    if task_result.get("count_increased"):
        score += 10
        feedback.append("Database: Branch count increased.")

    # Criteria B: VLM Trajectory Verification (50 points)
    # We use trajectory frames to ensure the user actually used the UI form
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with AttendHRM software.
    The user task is to add a new branch named "Downtown Office".
    
    Look for:
    1. A form or window titled "Branch" or "Office Location".
    2. Input fields being filled with "Downtown Office", "DTN", "San Francisco".
    3. The final state showing the new branch in a list.
    
    Return JSON:
    {
        "form_seen": boolean,
        "data_entry_seen": boolean,
        "success_confirmation_seen": boolean,
        "confidence": float (0-1)
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames + [final_frame])
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("form_seen"):
            vlm_score += 15
            feedback.append("VLM: Branch form detected.")
        if parsed.get("data_entry_seen"):
            vlm_score += 20
            feedback.append("VLM: Data entry detected.")
        if parsed.get("success_confirmation_seen"):
            vlm_score += 15
            feedback.append("VLM: Success confirmation detected.")
    else:
        feedback.append("VLM analysis failed.")
    
    score += vlm_score

    # Final Pass Check
    # Must have either DB record OR strong VLM evidence of completion
    passed = (task_result.get("record_found") and score >= 60) or (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }