#!/usr/bin/env python3
"""
Verifier for batch_import_customers task.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_import_customers(traj, env_info, task_info):
    """
    Verify the batch import of customers.
    
    Scoring Criteria:
    1. Customer Count Increase (+40 pts): Did the count go up by exactly 4?
    2. Specific Names Found (+30 pts): Are the 4 specific names present?
    3. File Access/Data Integrity (+10 pts): Was source file accessed / email visible?
    4. VLM Workflow Verification (+20 pts): Did the agent use "Batch Create"?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Count Check
    initial = result.get("initial_count", 0)
    final = result.get("final_count", 0)
    delta = final - initial
    
    if delta == 4:
        score += 40
        feedback.append("Correct number of customers added (+4).")
    elif delta > 0:
        partial = min(30, delta * 10)
        score += partial
        feedback.append(f"Added {delta} customers (expected 4).")
    else:
        feedback.append("No new customers detected.")

    # 2. Names Check
    names_found = result.get("names_found_count", 0)
    # 30 points max, 7.5 per name
    name_score = int(names_found * 7.5)
    score += name_score
    if names_found == 4:
        feedback.append("All customer names found.")
    else:
        feedback.append(f"Found {names_found}/4 expected customer names.")

    # 3. File Access / Data Integrity
    # If the file wasn't accessed, they might have made it up or typed it manually
    if result.get("source_file_accessed", False):
        score += 5
        feedback.append("Source file was accessed.")
    
    if result.get("email_visible_in_list", False):
        score += 5
        feedback.append("Customer email verified in list.")

    # 4. VLM Verification for Batch Create usage
    # We look for the specific "Batch Create" UI which is a large text area
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying if the user used the 'Batch Create' feature in Manager.io.
    
    Look for a screen that:
    1. Contains the text "Batch Create" or "Batch Create Customers".
    2. Shows a large multi-line text input area where data is pasted.
    3. Shows a table of data preview before confirmation.
    
    Did the user perform a Batch Create operation?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    batch_create_confirmed = False
    if vlm_result and vlm_result.get('success'):
        # Simple heuristic check on response
        response_lower = str(vlm_result).lower()
        if "yes" in response_lower and ("batch" in response_lower or "paste" in response_lower):
            batch_create_confirmed = True
            score += 20
            feedback.append("VLM confirmed usage of Batch Create feature.")
        else:
            feedback.append("VLM could not confirm Batch Create usage.")
    else:
        feedback.append("VLM verification skipped/failed.")

    # Final Pass/Fail
    passed = (score >= 70) and (names_found >= 4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }