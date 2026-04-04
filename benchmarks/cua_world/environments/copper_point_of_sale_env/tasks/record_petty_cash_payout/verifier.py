#!/usr/bin/env python3
"""
Verifier for record_petty_cash_payout task (Copper POS).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_record_petty_cash_payout(traj, env_info, task_info):
    """
    Verify that the petty cash payout was recorded and reported.
    
    Criteria:
    1. Output report file exists and was created during task (30 pts)
    2. Internal database record found for "Printer Paper Rolls" (40 pts)
    3. VLM verification of payout workflow (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Verification (30 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    
    if output_exists and created_during:
        if file_size > 1000: # Reasonable size for a PDF > 1KB
            score += 30
            feedback_parts.append("Report file created successfully")
        else:
            score += 10
            feedback_parts.append("Report file exists but is suspicious (too small)")
    elif output_exists:
        score += 5
        feedback_parts.append("Report file exists but timestamp indicates it wasn't created during this task")
    else:
        feedback_parts.append("Report file not found")

    # 2. Database/Transaction Verification (40 pts)
    # This proves the data was actually entered into the system, not just a fake PDF made
    db_found = result.get('transaction_found_in_db', False)
    
    if db_found:
        score += 40
        feedback_parts.append("Transaction verified in Copper database files")
    else:
        feedback_parts.append("Transaction NOT found in internal database (did you save it?)")

    # 3. VLM Verification (30 pts)
    # Use trajectory to confirm the workflow (Transactions -> Payout -> Report)
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user using NCH Copper Point of Sale software.
    I am looking for evidence of a "Petty Cash Payout" or "Cash Drop" workflow.
    
    Look for:
    1. A dialog or screen showing "Payout", "Cash Drop", or "Expense".
    2. Input of the amount "$15.00".
    3. Input of the description "Printer Paper Rolls".
    4. A report preview or generation screen.
    
    Does the user appear to have successfully recorded a payout transaction?
    Respond with JSON: {"success": true/false, "confidence": 0-1, "evidence": "description"}
    """
    
    try:
        vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
        vlm_data = vlm_result.get('parsed', {}) if vlm_result.get('success') else {}
        
        if vlm_data.get('success', False):
            score += 30
            feedback_parts.append(f"VLM verified workflow: {vlm_data.get('evidence', 'workflow observed')}")
        else:
            # Partial credit if DB passed but VLM unsure (maybe obscure UI)
            if db_found:
                score += 10 
            feedback_parts.append("VLM could not clearly verify visual workflow")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB check passed, give partial points
        if db_found:
            score += 15
            feedback_parts.append("VLM check unavailable, partial credit granted based on DB")

    # App running check (prerequisite)
    if not result.get('app_was_running', False):
        feedback_parts.append("WARNING: Copper POS was not running at end of task")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }