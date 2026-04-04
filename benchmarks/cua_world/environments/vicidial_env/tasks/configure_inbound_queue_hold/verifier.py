#!/usr/bin/env python3
"""
Verifier for configure_inbound_queue_hold task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_inbound_queue_hold(traj, env_info, task_info):
    """
    Verify that the Inbound Group 'SUPPORT' was created and configured correctly.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    data = result.get('data', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Group Existence (10 pts)
    if result.get('group_exists', False):
        score += 10
        feedback_parts.append("Group 'SUPPORT' created")
    else:
        return {"passed": False, "score": 0, "feedback": "Inbound Group 'SUPPORT' not found in database"}

    # 2. Basic Configuration (10 pts)
    # Active should be 'Y', Name should contain "Support"
    if data.get('active') == 'Y':
        score += 5
    else:
        feedback_parts.append("Group not set to Active")
        
    if "Support" in data.get('group_name', '') or "support" in data.get('group_name', ''):
        score += 5
    else:
        feedback_parts.append("Group name incorrect")

    # 3. Periodic Announcements (30 pts)
    pa_time = str(data.get('periodic_announce_time', '0'))
    pa_file = data.get('periodic_announce_filename', '')
    
    if pa_time == str(metadata.get('expected_announce_time', 60)):
        score += 15
        feedback_parts.append("Periodic interval correct")
    else:
        feedback_parts.append(f"Periodic interval wrong (got {pa_time})")
        
    if pa_file == metadata.get('expected_announce_file', 'generic_hold'):
        score += 15
        feedback_parts.append("Periodic file correct")
    else:
        feedback_parts.append(f"Periodic file wrong (got {pa_file})")

    # 4. Place in Line (10 pts)
    if data.get('play_place_in_line') == metadata.get('expected_place_in_line', 'Y'):
        score += 10
        feedback_parts.append("Place in line enabled")
    else:
        feedback_parts.append("Place in line not enabled")

    # 5. Hold Time Options (40 pts)
    ht_opt = data.get('hold_time_option', '')
    ht_sec = str(data.get('hold_time_option_seconds', '0'))
    ht_exten = data.get('hold_time_option_exten', '')
    ht_file = data.get('hold_time_option_press_filename', '')

    if ht_opt == metadata.get('expected_hold_opt', 'PRESS_VMAIL'):
        score += 10
        feedback_parts.append("Hold option type correct")
    else:
        feedback_parts.append(f"Hold option type wrong (got {ht_opt})")

    if ht_sec == str(metadata.get('expected_hold_seconds', 120)):
        score += 10
        feedback_parts.append("Hold wait time correct")
    else:
        feedback_parts.append(f"Hold wait time wrong (got {ht_sec})")

    if ht_exten == metadata.get('expected_hold_exten', '85100000'):
        score += 10
        feedback_parts.append("Voicemail extension correct")
    else:
        feedback_parts.append(f"Voicemail extension wrong (got {ht_exten})")
        
    if ht_file == metadata.get('expected_hold_file', 'vm-goodbye'):
        score += 10
        feedback_parts.append("Voicemail filename correct")
    else:
        feedback_parts.append(f"Voicemail filename wrong (got {ht_file})")

    # VLM Verification (Bonus/Confirmation)
    # Check if the agent actually visited the modification page
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Does the user appear to be configuring an Inbound Group in Vicidial? "
            "Look for form fields like 'Periodic Announce', 'Hold Time Option', or 'Place in Line'. "
            "Return JSON: {\"visiting_config_page\": true/false, \"confidence\": \"high/medium/low\"}"
        )
        try:
            vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
            if vlm_res.get("parsed", {}).get("visiting_config_page"):
                feedback_parts.append("VLM confirmed UI interaction")
            else:
                logger.warning("VLM did not confirm UI interaction")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final scoring
    passed = score >= 90  # Strict pass for configuration tasks
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }