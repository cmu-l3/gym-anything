#!/usr/bin/env python3
"""
Verifier for reconcile_bank_account task.

Criteria:
1. Reconciliation record exists in Manager.io (verified via API scrape).
2. Date is 31/01/2025 (or 2025-01-31).
3. Account is "Petty Cash".
4. Statement Balance is 170.00.
5. VLM verification of trajectory (optional but good for confirming process).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconcile_bank_account(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. Check programmatic results
    matches = result.get("matches", [])
    found_valid = False
    
    for match in matches:
        if match.get("date_match") and match.get("account_match") and match.get("balance_match"):
            found_valid = True
            break
            
    if found_valid:
        score += 70
        feedback_parts.append("Reconciliation record found with correct Date, Account, and Balance.")
    else:
        # Partial credit?
        if len(matches) > 0:
            score += 20
            feedback_parts.append("Reconciliation record found, but details (Date/Balance) incorrect.")
        else:
            feedback_parts.append("No reconciliation record found.")

    # 2. VLM Verification
    # We want to see the 'Reconciliation' screen or the 'Bank Reconciliations' list with the entry
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an accounting task in Manager.io.
    The user was supposed to create a Bank Reconciliation for 'Petty Cash' dated 31/01/2025 with a balance of 170.00.
    
    Look at the images:
    1. Do you see a form or list showing 'Bank Reconciliation'?
    2. Do you see 'Petty Cash'?
    3. Do you see the date '31/01/2025' or 'Jan 31, 2025'?
    4. Do you see the amount '170.00'?
    
    Return JSON: {"evidence_found": true/false, "details": "what you see"}
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames + [final_screen])
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("evidence_found"):
            score += 30
            feedback_parts.append("Visual evidence confirms reconciliation.")
        else:
            feedback_parts.append("Visual evidence unclear.")
    else:
        # If VLM fails, we don't penalize if programmatic passed perfectly
        if found_valid:
            score += 30
            feedback_parts.append("VLM skipped, trusting API check.")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }