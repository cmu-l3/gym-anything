#!/usr/bin/env python3
"""
Verifier for update_admin_profile task.
Checks:
1. Display Name matches "IT Operations"
2. Custom Status matches "Monitoring Systems"
3. Avatar ETag has changed (indicating upload)
4. VLM visual confirmation
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_admin_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
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
    
    # Criteria 1: Name Update (30 pts)
    final_name = result.get("final_name", "")
    expected_name = "IT Operations"
    if final_name == expected_name:
        score += 30
        feedback_parts.append("Name updated correctly.")
    else:
        feedback_parts.append(f"Name incorrect. Expected '{expected_name}', got '{final_name}'.")

    # Criteria 2: Status Update (30 pts)
    final_status = result.get("final_status", "")
    expected_status = "Monitoring Systems"
    if final_status == expected_status:
        score += 30
        feedback_parts.append("Status updated correctly.")
    else:
        feedback_parts.append(f"Status incorrect. Expected '{expected_status}', got '{final_status}'.")

    # Criteria 3: Avatar Changed (30 pts)
    # We rely on the ETag changing. If the agent uploaded the same image again, ETag might not change, 
    # but the task provides a specific NEW image, so it should change.
    initial_etag = result.get("initial_avatar_etag", "init")
    final_etag = result.get("final_avatar_etag", "final")
    
    # ETag is usually a short string. If it's missing, we can't verify.
    if final_etag and initial_etag and final_etag != initial_etag:
        score += 30
        feedback_parts.append("Avatar updated (ETag changed).")
    elif not final_etag:
        feedback_parts.append("Avatar verification failed (No ETag found).")
    else:
        feedback_parts.append("Avatar does not appear to have changed.")

    # Criteria 4: Visual Verification (10 pts)
    # Use VLM to confirm the changes are visible in the UI
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        prompt = """
        Analyze this screenshot of the Rocket.Chat interface.
        Look for the user profile or sidebar.
        1. Is the user name 'IT Operations' visible?
        2. Is the status 'Monitoring Systems' visible?
        3. Is there a blue profile picture with 'IT' text?
        
        Respond with JSON: {"name_visible": bool, "status_visible": bool, "avatar_visible": bool}
        """
        try:
            vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("name_visible") or parsed.get("status_visible") or parsed.get("avatar_visible"):
                    vlm_score = 10
                    feedback_parts.append("Visual confirmation successful.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Final Pass Logic
    # Strict: Must get Name, Status, and Avatar correct for pass.
    # VLM is bonus/confirmatory.
    passed = score >= 90

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }