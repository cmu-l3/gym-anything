#!/usr/bin/env python3
"""
Verifier for configure_member_server_audit task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_member_server_audit(traj, env_info, task_info):
    """
    Verifies that the agent added the member server with correct audit categories.
    
    Scoring:
    - 30 pts: Server 'APP-SERVER-01' found in system (Programmatic/Log check)
    - 20 pts: VLM confirms "Server Audit" page and server listed
    - 30 pts: VLM confirms enabled categories (Logon, Object Access, Privilege Use)
    - 20 pts: Workflow validity (screenshots show navigation)
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load programmatic result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            prog_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        prog_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []

    # 2. Programmatic Verification (30 pts)
    # Checks if export_result.sh found the server in DB or Logs
    if prog_result.get("server_found", False):
        score += 30
        feedback.append("Server 'APP-SERVER-01' detected in system configuration.")
    else:
        feedback.append("Server 'APP-SERVER-01' NOT detected in system configuration via script.")

    # 3. VLM Verification (70 pts total)
    # We use VLM to verify the UI state which is harder to query programmatically without full DB access
    
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    
    # Prompt for VLM
    prompt = """
    You are verifying an IT Admin task in ManageEngine ADAudit Plus.
    
    Goal: Add a Member Server named 'APP-SERVER-01' and enable 'Logon Activity', 'Object Access', and 'Privilege Use'.
    
    Review the final screenshot and the trajectory:
    1. Is the 'Server Audit' or 'Configured Servers' page visible?
    2. Is 'APP-SERVER-01' listed in the servers list?
    3. Are the checkboxes/indicators for 'Logon Activity', 'Object Access', and 'Privilege Use' checked/enabled?
    
    Output JSON:
    {
        "page_visible": boolean,
        "server_listed": boolean,
        "categories_checked": boolean,
        "workflow_steps_valid": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screenshot], prompt=prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Score breakdown
        if parsed.get("page_visible"):
            score += 10
            feedback.append("Correct configuration page visited.")
        
        if parsed.get("server_listed"):
            score += 20
            feedback.append("Server 'APP-SERVER-01' visible in the list.")
            
        if parsed.get("categories_checked"):
            score += 30
            feedback.append("Audit categories verified visually.")
        else:
             feedback.append("Could not visually verify all audit categories.")
             
        if parsed.get("workflow_steps_valid"):
            score += 10
            feedback.append("Workflow shows valid interaction steps.")
            
    else:
        feedback.append("VLM verification failed to process images.")

    # 4. Final Assessment
    passed = score >= 60  # Require at least server added (prog or visual) + some config
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }