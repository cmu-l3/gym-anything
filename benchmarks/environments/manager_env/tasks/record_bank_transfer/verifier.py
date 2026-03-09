#!/usr/bin/env python3
"""
Verifier for record_bank_transfer task.

Scores based on:
1. New transfer record creation (20 pts)
2. Correct Amount (3500.00) (20 pts)
3. Correct Source Account (10 pts)
4. Correct Destination Account (10 pts)
5. Correct Date (10 pts)
6. Correct Description/Ref (10 pts)
7. VLM Verification of trajectory (20 pts)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_bank_transfer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    parsed = result.get("parsed_data", {})
    
    # 1. Record Created (20 pts)
    if current_count > initial_count:
        score += 20
        feedback_parts.append("Transfer record created")
    else:
        feedback_parts.append("No new transfer record found")
        # Fail early if no record created
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Amount (20 pts)
    if parsed.get("amount_found"):
        score += 20
        feedback_parts.append("Amount correct (3,500.00)")
    else:
        feedback_parts.append("Amount mismatch")

    # 3. Source Account (10 pts)
    if parsed.get("source_found"):
        score += 10
        feedback_parts.append("Source account correct")
    else:
        feedback_parts.append("Source account incorrect")

    # 4. Dest Account (10 pts)
    if parsed.get("dest_found"):
        score += 10
        feedback_parts.append("Destination account correct")
    else:
        feedback_parts.append("Destination account incorrect")

    # 5. Date (10 pts)
    if parsed.get("date_found"):
        score += 10
        feedback_parts.append("Date correct")
    else:
        feedback_parts.append("Date incorrect")

    # 6. Description (10 pts)
    if parsed.get("desc_found"):
        score += 10
        feedback_parts.append("Description/Ref found")
    else:
        feedback_parts.append("Description missing ref #1045")

    # 7. VLM Verification (20 pts)
    # Use trajectory frames to confirm user interaction
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a user using accounting software.
        Did the user:
        1. Access the 'Inter Account Transfers' form?
        2. Enter '3500' in an amount field?
        3. Select 'Cash on Hand' and 'Business Checking Account'?
        
        Respond with JSON: {"form_accessed": bool, "amount_visible": bool, "accounts_visible": bool}
        """
        try:
            vlm_resp = query_vlm(prompt=vlm_prompt, images=frames)
            vlm_data = vlm_resp.get("parsed", {})
            
            vlm_score = 0
            if vlm_data.get("form_accessed"): vlm_score += 10
            if vlm_data.get("amount_visible") or vlm_data.get("accounts_visible"): vlm_score += 10
            
            score += vlm_score
            if vlm_score > 0:
                feedback_parts.append(f"VLM verified process (+{vlm_score})")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic checks passed mostly, give benefit of doubt
            if score >= 60:
                score += 10
                feedback_parts.append("VLM skipped (programmatic pass)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }