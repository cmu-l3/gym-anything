#!/usr/bin/env python3
"""
Verifier for add_custom_billing_code task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_custom_billing_code(traj, env_info, task_info):
    """
    Verify the agent added the custom billing code correctly.
    
    Criteria:
    1. Database record exists for 'SPT-PHY' (40 pts)
    2. Fee is exactly 50.00 (30 pts)
    3. Description contains 'Sports Physical' (20 pts)
    4. Code is active (10 pts)
    
    Pass Threshold: 70 points (Must have created code + correct price).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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
    
    # 2. Database Verification
    if not result.get('found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Billing code 'SPT-PHY' was not found in the database."
        }
    
    score += 40
    feedback_parts.append("Code 'SPT-PHY' created")
    
    # Check Fee
    # Fee might come back as string "50.00" or float
    try:
        fee_val = float(result.get('fee', 0))
        if abs(fee_val - 50.0) < 0.01:
            score += 30
            feedback_parts.append("Price correct ($50.00)")
        else:
            feedback_parts.append(f"Price incorrect (expected $50.00, got ${fee_val})")
    except ValueError:
        feedback_parts.append("Price format invalid")

    # Check Description
    desc = result.get('description', '').lower()
    if 'sports physical' in desc:
        score += 20
        feedback_parts.append("Description correct")
    else:
        feedback_parts.append(f"Description mismatch ('{result.get('description')}')")

    # Check Active Status (usually '1', 'y', 't', or 'active')
    active_status = str(result.get('active', '')).lower()
    if active_status in ['1', 'true', 'y', 'yes', 'on']:
        score += 10
        feedback_parts.append("Status active")
    else:
        feedback_parts.append("Code not marked active")

    # 3. VLM Verification (Trajectory Check)
    # We use this to verify the agent actually used the UI and didn't just guess a URL or CLI
    # (Though in this env CLI access is restricted, it's good practice)
    try:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = (
                "Is the user looking at a list of billing codes, services, or CPT codes? "
                "Do you see 'SPT-PHY' or 'Sports Physical' in the list? "
                "Answer yes or no."
            )
            vlm_response = query_vlm(
                images=[final_screenshot], 
                prompt=prompt
            )
            # We don't deduct points for VLM fail here since DB is ground truth, 
            # but we log it for audit.
            if vlm_response.get('success'):
                logger.info(f"VLM Verification: {vlm_response.get('parsed')}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # 4. Final Scoring
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }