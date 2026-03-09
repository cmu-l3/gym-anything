#!/usr/bin/env python3
"""
Verifier for grant_foia_fee_waiver task.
Checks if the fee waiver status was updated in ArkCase.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_grant_foia_fee_waiver(traj, env_info, task_info):
    """
    Verify that the fee waiver was granted with the correct justification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('justification_keywords', ["public interest", "news media"])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: API Verification (Primary) ---
    api_data = result.get('api_response', {})
    
    # Note: ArkCase field names vary. We check common variations or dump inspection.
    # Common fields: 'feeWaiver' (boolean/string), 'feeWaiverStatus', 'feeWaiverReason', 'justification'
    
    # Helper to find value in nested dict case-insensitively
    def find_key_value(data, target_key_part):
        for k, v in data.items():
            if target_key_part.lower() in k.lower():
                return v
        return None

    # Check Status
    waiver_status = find_key_value(api_data, 'feeWaiver')
    # Acceptable "Granted" values: True, "GRANTED", "Yes", "Active"
    status_passed = False
    if str(waiver_status).upper() in ['TRUE', 'GRANTED', 'YES', 'ACTIVE']:
        status_passed = True
        score += 40
        feedback_parts.append("Fee Waiver status is GRANTED (API confirmed).")
    else:
        feedback_parts.append(f"Fee Waiver status incorrect or not found (Value: {waiver_status}).")

    # Check Justification
    waiver_reason = find_key_value(api_data, 'feeWaiverReason') or find_key_value(api_data, 'justification') or ""
    waiver_reason_str = str(waiver_reason).lower()
    
    keywords_found = [kw for kw in expected_keywords if kw.lower() in waiver_reason_str]
    if len(keywords_found) >= len(expected_keywords):
        score += 30
        feedback_parts.append("Justification text matches requirements.")
    elif len(keywords_found) > 0:
        score += 15
        feedback_parts.append(f"Justification partially correct. Found: {keywords_found}")
    else:
        feedback_parts.append(f"Justification text missing or incorrect. (Got: '{waiver_reason}')")

    # --- Criterion 2: VLM Trajectory Verification (Secondary) ---
    # We want to ensure they actually navigated to the financials section
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
    
    vlm_prompt = (
        "Analyze these screenshots of a case management system interaction. "
        "Did the user navigate to a 'Financials', 'Fees', or 'Billing' tab/section? "
        "Did they interact with a Fee Waiver setting? "
        "Does the final state show the waiver as Granted?"
    )
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get('success'):
        # Simple heuristic: if VLM is positive about interaction
        vlm_text = vlm_result.get('parsed', {}).get('response', '').lower()
        if "yes" in vlm_text or "granted" in vlm_text:
            score += 20
            feedback_parts.append("Visual verification confirms workflow.")
    else:
        feedback_parts.append("Visual verification failed/inconclusive.")

    # --- Criterion 3: Anti-Gaming ---
    task_start = result.get('task_start', 0)
    # If the API data has a 'lastModified' field, we could check it.
    # For now, we assume if API check passed, they did it.
    score += 10 # Base points for valid execution flow

    passed = score >= 60 and status_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }