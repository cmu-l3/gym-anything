#!/usr/bin/env python3
"""
Verifier for configure_email_notifications task.

Strategies:
1. Programmatic: Check if the specific SMTP server string ("mail.acmetech.com") exists in config files/registry.
2. Programmatic: Check if an evidence screenshot was saved to the correct path.
3. VLM: Verify the content of the evidence screenshot matches requirements (settings visible).
4. VLM: Verify trajectory shows navigation to settings.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_email_notifications(traj, env_info, task_info):
    """
    Verify email notification configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Programmatic Checks (40 points)
    # ------------------------------------------------------------------
    
    # Check A: Config string found (20 pts)
    config_found = result.get("config_string_found", False)
    config_time_valid = result.get("config_timestamp_valid", False)
    
    if config_found:
        if config_time_valid:
            score += 20
            feedback_parts.append("SMTP settings found in configuration files (Modified correctly)")
        else:
            score += 10
            feedback_parts.append("SMTP settings found, but file timestamp questionable (pre-existing?)")
    else:
        feedback_parts.append("SMTP settings NOT found in configuration files")

    # Check B: Evidence screenshot file exists (20 pts)
    evidence_exists = result.get("evidence_screenshot_exists", False)
    
    if evidence_exists:
        score += 20
        feedback_parts.append("Evidence screenshot saved to correct path")
    else:
        feedback_parts.append("Evidence screenshot NOT found at C:\\LobbyTrack\\email_config_evidence.png")

    # ------------------------------------------------------------------
    # 2. VLM Verification (60 points)
    # ------------------------------------------------------------------
    
    # Retrieve evidence screenshot if it exists, otherwise use final screenshot
    image_to_verify = None
    if evidence_exists:
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/evidence_screenshot.png", temp_img.name)
            image_to_verify = temp_img.name
        except Exception as e:
            logger.warning(f"Could not copy evidence screenshot: {e}")
    
    if not image_to_verify:
        image_to_verify = get_final_screenshot(traj)

    if not image_to_verify:
         return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | No screenshots available for visual verification"
        }

    # Prompt for VLM
    prompt = """
    You are verifying a screenshot from "Jolly Lobby Track" software.
    The user was asked to configure Email/SMTP Notification settings.
    
    Please check for the following in the image:
    1. Is an Email, Notification, or SMTP settings screen visible?
    2. Is the SMTP Server set to "mail.acmetech.com"?
    3. Is the Port set to "587"?
    4. Is the Username/Email set to "lobby@acmetech.com"?
    5. Are notifications enabled/checked?
    
    Return JSON:
    {
        "settings_screen_visible": boolean,
        "server_correct": boolean,
        "port_correct": boolean,
        "user_correct": boolean,
        "notifications_enabled": boolean,
        "confidence": "low"|"medium"|"high"
    }
    """

    vlm_result = query_vlm(
        prompt=prompt,
        image=image_to_verify
    )
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("settings_screen_visible"):
            vlm_score += 10
            feedback_parts.append("VLM: Settings screen visible")
            
            # Detailed field checks
            if parsed.get("server_correct"): 
                vlm_score += 15
                feedback_parts.append("VLM: Server address correct")
            else:
                feedback_parts.append("VLM: Server address missing/incorrect")
                
            if parsed.get("port_correct"):
                vlm_score += 10
                feedback_parts.append("VLM: Port correct")
                
            if parsed.get("user_correct"):
                vlm_score += 10
                feedback_parts.append("VLM: Username correct")
                
            if parsed.get("notifications_enabled"):
                vlm_score += 15
                feedback_parts.append("VLM: Notifications enabled")
        else:
            feedback_parts.append("VLM: Settings screen NOT detected in screenshot")
    else:
        feedback_parts.append("VLM verification failed to execute")

    score += vlm_score

    # Clean up temp file
    if image_to_verify and os.path.exists(image_to_verify):
        try:
            os.unlink(image_to_verify)
        except:
            pass

    passed = (score >= 60) and config_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }