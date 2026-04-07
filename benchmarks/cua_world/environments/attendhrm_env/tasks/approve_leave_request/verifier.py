#!/usr/bin/env python3
"""
Verifier for approve_leave_request task.
Checks:
1. Target request (Anita Roy) is APPROVED (Status 2).
2. Decoy request (Rajiv Menon) is NOT approved (Status 1).
3. VLM verification of the workflow.
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available")

def verify_approve_leave_request(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/temp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Database Status Verification
    # AttendHRM Status Codes: 1=Applied, 2=Sanctioned(Approved), 3=Rejected
    
    anita_status = str(result.get('anita_status', '-1')).strip()
    rajiv_status = str(result.get('rajiv_status', '-1')).strip()
    
    # Target Check (Anita) - 50 points
    target_passed = False
    if anita_status == '2':
        score += 50
        target_passed = True
        feedback_parts.append("Target request (Anita) correctly Approved.")
    elif anita_status == '3':
        feedback_parts.append("Target request (Anita) was Rejected instead of Approved.")
    elif anita_status == '1':
        feedback_parts.append("Target request (Anita) is still Pending.")
    else:
        feedback_parts.append(f"Target request status unknown/missing (Code: {anita_status}).")

    # Decoy Check (Rajiv) - 20 points
    # Must NOT be 2. Ideally 1.
    decoy_passed = False
    if rajiv_status == '1':
        score += 20
        decoy_passed = True
        feedback_parts.append("Decoy request (Rajiv) correctly ignored.")
    elif rajiv_status == '2':
        feedback_parts.append("Decoy request (Rajiv) was INCORRECTLY Approved.")
    elif rajiv_status == '3':
        feedback_parts.append("Decoy request (Rajiv) was Rejected (Acceptable but not requested).")
        score += 10 # Partial credit for at least handling it? No, instruction was to ignore.
    else:
        # If status missing, maybe data issue
        if rajiv_status == '-1':
             feedback_parts.append("Decoy request data not found.")
        else:
             score += 20 # Assume ok if not approved
             feedback_parts.append(f"Decoy request status: {rajiv_status}")

    # 3. VLM Verification - 30 points
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        You are verifying an HR agent's task execution.
        Task: Approve a leave request for 'Anita Roy'.
        
        Review the screenshots.
        1. Did the agent navigate to a Leave Application/Management screen?
        2. Is 'Anita Roy' visible in the list?
        3. Did the agent click an 'Approve', 'Sanction', or checkmark button?
        4. Is there visual confirmation of success (status change to green/Approved)?
        
        Return JSON: {"success": bool, "score": int_0_to_30, "reason": "str"}
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                vlm_score = parsed.get("score", 0)
                feedback_parts.append(f"Visual Verification: {parsed.get('reason', 'Analyzed')}")
            else:
                # Fallback if VLM fails
                if target_passed: vlm_score = 15
        except Exception:
            if target_passed: vlm_score = 15
    else:
        # Fallback score if VLM not available but DB passed
        if target_passed: vlm_score = 30
        feedback_parts.append("VLM verification skipped (modules not found).")

    score += vlm_score

    # Final Check
    passed = (score >= 70) and target_passed and decoy_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }