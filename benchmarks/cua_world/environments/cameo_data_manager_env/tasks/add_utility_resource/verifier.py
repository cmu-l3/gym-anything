#!/usr/bin/env python3
"""
Verifier for add_utility_resource task.

Since CAMEO Data Manager uses a proprietary database format that is difficult 
to query directly without specific drivers, this verifier relies on:
1. File System Modification: Verifying that CAMEO data files were updated.
2. VLM Verification: Using Vision Language Models to verify the data entry 
   on the screen (Primary Verification).
3. Application State: Verifying the application is running.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_utility_resource(traj, env_info, task_info):
    """
    Verify that the PG&E utility resource was added correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Pacific Gas and Electric Company")
    expected_phone = metadata.get('expected_phone', "800-743-5000")
    expected_contact = metadata.get('expected_contact', "Maria Gonzalez")

    # Load result JSON from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: We assume the Windows C:\tmp\task_result.json is mapped/accessible via this path
        # or the copy_from_env handles the abstraction.
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        # Fallback: Create default failed result if file read fails
        result = {"app_running": False, "data_modified": False}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Application Running (10 pts)
    if result.get("app_running"):
        score += 10
        feedback_parts.append("CAMEO is running.")
    else:
        feedback_parts.append("CAMEO is NOT running.")

    # Criterion 2: Data Modified (20 pts)
    # This proves the agent actually saved something
    if result.get("data_modified"):
        score += 20
        feedback_parts.append("Data files modified (save detected).")
    else:
        feedback_parts.append("No data saved.")

    # Criterion 3: VLM Verification (70 pts)
    # We check the final state and trajectory
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    if not final_screenshot:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No screenshots available for verification."
        }

    # Construct VLM prompt
    prompt = f"""
    You are verifying if a user successfully added a specific Utility Resource in CAMEO Data Manager.
    
    TARGET DATA:
    - Name: {expected_name}
    - Phone: {expected_phone}
    - Contact: {expected_contact}
    - Address: San Francisco, CA
    
    Look at the screenshots (especially the last one).
    1. Is the "Pacific Gas and Electric Company" record visible?
    2. Are the details (Phone, Contact Person, Address) visible and correct?
    3. Is the record saved (not just in edit mode)?
    
    Respond in JSON:
    {{
        "record_visible": true/false,
        "details_match": true/false,
        "saved": true/false,
        "confidence": "low/medium/high"
    }}
    """
    
    # Query VLM with history to catch if they were on the screen but navigated away
    images = frames + [final_screenshot]
    vlm_resp = query_vlm(images=images, prompt=prompt)
    
    vlm_score = 0
    if vlm_resp.get("success"):
        parsed = vlm_resp.get("parsed", {})
        
        if parsed.get("record_visible"):
            vlm_score += 30
            feedback_parts.append("PG&E record visible.")
        
        if parsed.get("details_match"):
            vlm_score += 20
            feedback_parts.append("Details (Phone/Contact) match.")
            
        if parsed.get("saved"):
            vlm_score += 20
            feedback_parts.append("Record appears saved.")
            
    score += vlm_score

    passed = score >= 60 and result.get("data_modified") and vlm_score >= 30
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }