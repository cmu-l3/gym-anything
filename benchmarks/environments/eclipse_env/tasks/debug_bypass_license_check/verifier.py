#!/usr/bin/env python3
"""Verifier for debug_bypass_license_check task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_bypass_license_check(traj, env_info, task_info):
    """
    Verify the agent bypassed the license check using the debugger.

    Scoring Criteria:
    1. Log file exists and contains success token (40 pts)
    2. Log file was created during the task (anti-gaming) (10 pts)
    3. Source code integrity: LicenseManager.java NOT modified (30 pts)
    4. VLM: Debugger usage (Variables view, Debug perspective) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_token = metadata.get('success_token', 'SUCCESS_TOKEN_BYPASS_COMPLETE')

    # Read result JSON
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
    
    # --- Criterion 1 & 2: Log File Success (50 pts total) ---
    log_found = result.get('log_found', False)
    log_content = result.get('log_content', '')
    log_created_during = result.get('log_created_during_task', False)

    if log_found and expected_token in log_content:
        if log_created_during:
            score += 50
            feedback_parts.append("Success log generated correctly")
        else:
            score += 10
            feedback_parts.append("Log found but timestamp predates task (stale data?)")
    else:
        feedback_parts.append("Success log NOT found or invalid content")

    # --- Criterion 3: Code Integrity (30 pts) ---
    # The agent must NOT modify the source code to pass the check.
    code_modified = result.get('code_modified', True)
    
    if not code_modified:
        score += 30
        feedback_parts.append("Source code integrity maintained (Clean)")
    else:
        feedback_parts.append("FAIL: LicenseManager.java was modified! (Must use debugger)")
        # Serious penalty: if they hacked the code, they fail the "debug" aspect entirely.
        # We might cap the score or just give 0 for this section.
        # If the log exists BUT code is modified, they technically cheated the instructions.
        # We will not fail the whole task immediately but give 0 for this part.

    # --- Criterion 4: VLM Verification (20 pts) ---
    # Verify visual evidence of debugging
    vlm_score = 0
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        checklist = [
            "Eclipse Debug perspective is active (bug icon, specific layout)",
            "Variables view is visible",
            "Breakpoint marker visible in editor gutter",
            "Console shows 'Server Started Successfully'"
        ]
        
        vlm_out = vlm_verify_eclipse_task(traj, env_info, task_info.get('description', ''), checklist)
        
        if vlm_out:
            vlm_score = min(vlm_out.get('vlm_score', 0), 20)
            feedback_parts.append(vlm_out.get('vlm_feedback', ''))
            
            # Boost VLM score if result JSON says debug perspective was active
            if result.get('debug_perspective_active') and vlm_score < 10:
                vlm_score += 5
                feedback_parts.append("(Window title confirms Debug perspective)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM check skipped")
    
    score += int(vlm_score)

    # --- Final Pass Determination ---
    # Must have the log file AND code integrity to pass.
    passed = (log_found and log_created_during and not code_modified and score >= 70)

    if log_found and code_modified:
        feedback_parts.append("TASK FAILED: You modified the source code instead of using the debugger.")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }