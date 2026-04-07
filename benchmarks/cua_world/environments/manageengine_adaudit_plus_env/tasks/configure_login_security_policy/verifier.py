#!/usr/bin/env python3
"""
Verifier for configure_login_security_policy task.

Uses a Hybrid Verification Strategy:
1. Anti-Gaming: Checks file modification timestamps (did the agent actually change config files?)
2. VLM: Visually confirms the settings are correct on the final screen.
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_configure_login_security_policy(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the ADAudit Plus login security policy was configured correctly.
    """
    
    # 1. Setup & Read Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Import shared VLM utilities (mock import for standalone file)
    try:
        from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
    except ImportError:
        # Fallback if specific library not found, assuming local verifier context
        def get_final_screenshot(traj): return traj[-1].get('screenshot') if traj else None
        def sample_trajectory_frames(traj, n): return [t.get('screenshot') for t in traj[-n:]] if traj else []
        def query_vlm(**kwargs): return {"success": False, "error": "VLM not mocked"}

    # Load programmatic result from container
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    programmatic_result = {}
    
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            programmatic_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
        # We proceed, but score will likely be lower on anti-gaming
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. VLM Verification (Primary Signal)
    # We ask the VLM to read the values from the screen
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}

    prompt = """
    You are verifying an IT configuration task in ManageEngine ADAudit Plus.
    
    The user was asked to configure 'Logon Settings' with these values:
    1. Session Expiry Time: 20 minutes
    2. Account Lockout Threshold: 3 attempts
    3. Account Lockout Duration: 30 minutes
    
    Look at the screenshot and determine:
    - Is the 'Logon Settings' or 'Admin' page visible?
    - Can you see the 'Session Expiry Time' field? What is the value?
    - Can you see the 'Account Lockout Threshold' field? What is the value?
    - Can you see the 'Account Lockout Duration' field? What is the value?
    - Does the interface look like the settings were saved (no red error text)?
    
    Output JSON:
    {
        "page_visible": boolean,
        "session_expiry_value": "string or null",
        "lockout_threshold_value": "string or null",
        "lockout_duration_value": "string or null",
        "values_match_task": boolean,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_response = query_vlm(
        images=[final_screenshot],
        prompt=prompt
    )
    
    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion A: Configuration/File Activity (Anti-Gaming) - 20 pts
    files_modified_count = programmatic_result.get("files_modified_count", 0)
    log_evidence = programmatic_result.get("log_evidence_found", False)
    
    if files_modified_count > 0 or log_evidence:
        score += 20
        feedback.append("System activity detected (files/logs modified).")
    else:
        feedback.append("Warning: No file system activity detected (did you save?).")

    # Criterion B: VLM Visual Confirmation - 80 pts
    if vlm_response.get("success"):
        data = vlm_response.get("parsed", {})
        
        # Check Page Visibility
        if data.get("page_visible"):
            score += 10
            feedback.append("Correct settings page reached.")
        
        # Check Values (Flexible matching)
        # Session Expiry (Target: 20)
        s_exp = str(data.get("session_expiry_value", ""))
        if "20" in s_exp:
            score += 25
            feedback.append("Session Expiry set to 20.")
        else:
            feedback.append(f"Session Expiry mismatch (saw '{s_exp}', expected '20').")

        # Lockout Threshold (Target: 3)
        l_thr = str(data.get("lockout_threshold_value", ""))
        if "3" in l_thr:
            score += 20
            feedback.append("Lockout Threshold set to 3.")
        else:
            feedback.append(f"Lockout Threshold mismatch (saw '{l_thr}', expected '3').")

        # Lockout Duration (Target: 30)
        l_dur = str(data.get("lockout_duration_value", ""))
        if "30" in l_dur:
            score += 25
            feedback.append("Lockout Duration set to 30.")
        else:
            feedback.append(f"Lockout Duration mismatch (saw '{l_dur}', expected '30').")
            
    else:
        feedback.append("Visual verification failed (VLM error).")

    # Final result
    passed = score >= 80  # Requires most settings correct + visible
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }