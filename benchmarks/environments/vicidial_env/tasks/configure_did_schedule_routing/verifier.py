#!/usr/bin/env python3
"""
Verifier for configure_did_schedule_routing task.

Checks if the Vicidial DID record is correctly updated to use time-based routing.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_did_schedule_routing(traj, env_info, task_info):
    """
    Verifies the DID routing configuration.
    
    Criteria:
    1. Call Time ID set to '9am-5pm' (30 pts)
    2. Filter Action set to 'VOICEMAIL' or 'EXTEN' (25 pts)
    3. Filter Extension directs to '8500' (25 pts)
    4. Clean CID Number is 'Y' (10 pts)
    5. VLM: Agent visited the DID modification page (10 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    did_config = result.get('did_config')
    
    if not did_config:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "DID record 8885559999 not found in database. It may have been deleted."
        }

    score = 0
    feedback_parts = []
    
    # 1. Check Call Time (30 pts)
    # The requirement is 9am-5pm
    call_time = did_config.get('call_time_id', '')
    if call_time == '9am-5pm':
        score += 30
        feedback_parts.append("Call Time correctly set to 9am-5pm.")
    else:
        feedback_parts.append(f"Incorrect Call Time: '{call_time}' (expected '9am-5pm').")

    # 2. Check Filter Action (25 pts)
    # Should be VOICEMAIL (or EXTEN if they manually routed it)
    action = did_config.get('filter_action', '')
    if action == 'VOICEMAIL':
        score += 25
        feedback_parts.append("Filter Action correctly set to VOICEMAIL.")
    elif action == 'EXTEN':
        # If they use EXTEN, we need to check if they point to voicemail extension logic
        score += 20
        feedback_parts.append("Filter Action set to EXTEN (acceptable).")
    else:
        feedback_parts.append(f"Incorrect Filter Action: '{action}' (expected VOICEMAIL).")

    # 3. Check Filter Extension (25 pts)
    # Should be 8500
    extension = did_config.get('filter_extension', '')
    if '8500' in extension:
        score += 25
        feedback_parts.append(f"Filter Extension correctly targets 8500.")
    else:
        feedback_parts.append(f"Incorrect Filter Extension: '{extension}' (expected 8500).")

    # 4. Check Clean CID (10 pts)
    clean_cid = did_config.get('filter_clean_cid_number', '')
    if clean_cid == 'Y':
        score += 10
        feedback_parts.append("Clean CID Number enabled.")
    else:
        feedback_parts.append(f"Clean CID Number not enabled.")

    # 5. VLM Check (10 pts)
    # Verify they actually used the UI
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        # We look for the "Modify DID" header or form elements
        prompt = "Is the user interacting with a form titled 'Modify DID' or editing phone number routing settings?"
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success') and (vlm_res.get('parsed', {}).get('answer') == True or 'yes' in str(vlm_res.get('response', '')).lower()):
            vlm_score = 10
            feedback_parts.append("VLM confirmed UI interaction.")
        else:
            feedback_parts.append("VLM could not confirm specific UI interaction (minor).")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if database score is high, assume they used UI
        if score >= 80:
            vlm_score = 10
            feedback_parts.append("Implicit UI interaction verified by DB state.")

    score += vlm_score

    # Final Pass/Fail
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }