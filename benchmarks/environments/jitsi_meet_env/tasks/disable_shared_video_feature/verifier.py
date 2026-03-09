#!/usr/bin/env python3
"""
Verifier for disable_shared_video_feature task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_shared_video(traj, env_info, task_info):
    """
    Verifies that the shared video feature was disabled in config and UI.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check Configuration (Primary verification)
    container_found = result.get("container_found", False)
    has_shared = result.get("config_has_sharedvideo")
    has_mic = result.get("config_has_mic")
    valid_js = result.get("config_valid_js")

    if not container_found:
        return {"passed": False, "score": 0, "feedback": "Jitsi web container not found"}

    # Criterion: 'sharedvideo' removed (40 pts)
    if has_shared == "false":
        score += 40
        feedback.append("Config: 'sharedvideo' removed successfully")
    elif has_shared == "true":
        feedback.append("Config: 'sharedvideo' still present")
    else:
        feedback.append("Config: Could not determine state")

    # Criterion: Syntax valid (20 pts)
    if valid_js == "true":
        score += 20
        feedback.append("Config: Syntax is valid")
    elif valid_js == "false":
        feedback.append("Config: Syntax error in file")

    # Criterion: Sanity check - didn't delete everything (10 pts)
    if has_mic == "true":
        score += 10
        feedback.append("Config: Other buttons preserved")
    else:
        feedback.append("Config: WARNING - Other buttons missing/deleted")

    # 3. VLM Verification (UI check - 30 pts)
    # We look at the final screenshot to see if the menu is open and item is gone
    final_img = get_final_screenshot(traj)
    
    # We also check a few frames back in case they opened it and then it closed
    frames = sample_trajectory_frames(traj, n=3)
    
    vlm_prompt = """
    You are verifying a Jitsi Meet task. The goal is to verify the "Share a YouTube video" option is GONE from the "More actions" menu.
    
    Look at the screenshot(s).
    1. Is the Jitsi Meet interface visible?
    2. Is the "More actions" menu (popup list of options) open?
    3. If the menu is open, do you see "Share video" or "Share a YouTube video"?
    
    Reply JSON:
    {
        "menu_open": true/false,
        "share_video_option_visible": true/false,
        "feedback": "string"
    }
    """
    
    # Use the final screenshot primarily
    vlm_score = 0
    if final_img:
        try:
            vlm_res = query_vlm(images=[final_img], prompt=vlm_prompt).get("parsed", {})
            
            if vlm_res.get("menu_open"):
                if not vlm_res.get("share_video_option_visible"):
                    vlm_score = 30
                    feedback.append("UI: Verified menu open and option absent")
                else:
                    feedback.append("UI: Option still visible in menu")
            else:
                feedback.append("UI: Menu not visible in final screenshot")
                # Fallback: check if config was correct, give partial credit?
                # The prompt implies they should keep it open.
        except Exception as e:
            feedback.append(f"VLM error: {e}")
    
    score += vlm_score

    # Pass threshold
    passed = (score >= 60) and (has_shared == "false")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }