#!/usr/bin/env python3
"""
Verifier for discontinue_medication task.

Criteria:
1. Database: A DISCONTINUE order exists linked to the target order (30 pts)
2. Database: Original order has date_stopped set (25 pts)
3. Anti-gaming: Action timestamp > Task start timestamp (10 pts)
4. REST API: Target order is no longer in active list (20 pts)
5. VLM: Trajectory shows medication list interaction (15 pts)

Pass Threshold: 55 points (Must at least have DB evidence of discontinuation)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_discontinue_medication(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Evaluate Programmatic Criteria
    
    # Crit 1: DISCONTINUE order exists
    disc_count = int(result.get("discontinue_order_db_count", 0))
    if disc_count >= 1:
        score += 30
        feedback.append("Success: Discontinue order record found in database.")
    else:
        feedback.append("Fail: No 'DISCONTINUE' order action found in database.")

    # Crit 2: Original order stopped
    if result.get("original_order_stopped", False):
        score += 25
        feedback.append("Success: Original order marked as stopped.")
    else:
        feedback.append("Fail: Original order is not marked as stopped.")

    # Crit 3: Anti-gaming Timestamp
    if result.get("action_performed_after_start", False):
        score += 10
        feedback.append("Success: Action performed during task session.")
    else:
        if disc_count >= 1:
            feedback.append("Fail: Action timestamp predates task start (pre-existing condition?).")
        else:
            feedback.append("Fail: No action timestamp to verify.")

    # Crit 4: REST API confirmation
    if not result.get("is_active_in_rest", True): # Expect False for active
        score += 20
        feedback.append("Success: Medication verified inactive via REST API.")
    else:
        feedback.append("Fail: Medication still appears active in REST API.")

    # 3. VLM Verification (Trajectory)
    # Check if agent visited medication tab or interacted with order list
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Analyze these screenshots of the OpenMRS Electronic Health Record system.
        The user is supposed to discontinue (stop) a medication called 'Aspirin'.
        
        Look for:
        1. A list of medications or orders.
        2. A menu or button click related to 'Discontinue', 'Stop', or an 'X' icon next to Aspirin.
        3. A confirmation dialog asking for a reason to discontinue.
        4. The final state showing Aspirin in a 'Inactive' or 'Stopped' section, or removed from Active.
        
        Did the user perform the discontinuation workflow?
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res and vlm_res.get('success'):
            # Simple heuristic based on positive VLM response
            vlm_text = vlm_res.get('response', '').lower()
            if "yes" in vlm_text or "perform" in vlm_text or "discontinue" in vlm_text:
                score += 15
                feedback.append("Success: Visual evidence of discontinuation workflow.")
            else:
                feedback.append("Warning: Visual evidence unclear.")
        else:
            feedback.append("Warning: VLM verification failed to run.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails technically, but don't award points if totally broken
        pass

    passed = (score >= 55) and (disc_count >= 1) and result.get("original_order_stopped", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }