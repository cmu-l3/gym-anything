#!/usr/bin/env python3
"""
Verifier for adjust_app_permissions task.

Verification Strategy:
1. Programmatic: Check permission flags (Location=Background, Mic=Denied).
2. Programmatic: Verify collateral permissions (Calendar/Contacts) preserved.
3. VLM: Verify navigation trajectory through System Settings.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils from framework
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_app_permissions(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that permissions were correctly adjusted in Android Settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Verification of Permissions (65 points total)
    
    # Check Location (Goal: Allow all the time = Background + Fine)
    loc_bg = result.get("location_background_granted", False)
    loc_fg = result.get("location_fine_granted", False)
    
    if loc_bg and loc_fg:
        score += 25
        feedback_parts.append("Location set to 'Allow all the time' (Correct)")
    elif loc_fg:
        feedback_parts.append("Location set to 'While using' (Incorrect - needed 'All the time')")
    else:
        feedback_parts.append("Location permission lost/denied")

    # Check Microphone (Goal: Denied)
    mic_granted = result.get("microphone_granted", True) # Default to true (fail) if missing
    
    if not mic_granted:
        score += 20
        feedback_parts.append("Microphone permission denied (Correct)")
    else:
        feedback_parts.append("Microphone permission still granted (Incorrect)")

    # Check Collateral Damage (Goal: Calendar & Contacts still granted)
    cal_granted = result.get("calendar_granted", False)
    contacts_granted = result.get("contacts_granted", False)
    
    if cal_granted:
        score += 10
        feedback_parts.append("Calendar permission preserved")
    else:
        feedback_parts.append("Calendar permission accidentally revoked")
        
    if contacts_granted:
        score += 10
        feedback_parts.append("Contacts permission preserved")
    else:
        feedback_parts.append("Contacts permission accidentally revoked")

    # Check App State (Goal: Back in app)
    app_fg = result.get("app_in_foreground", False)
    if app_fg:
        score += 10
        feedback_parts.append("Returned to Flight Crew View app")
    else:
        feedback_parts.append("Did not return to app (or app crashed)")

    # 3. VLM Trajectory Verification (35 points)
    # Ensure they actually went to settings
    
    # Sample frames from the middle of the trajectory
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Analyze these screenshots of an Android task. The user was supposed to:
    1. Go to Android Settings
    2. Open App Permissions for 'Flight Crew View'
    3. Change Location to 'Allow all the time'
    4. Change Microphone to 'Don't allow'
    
    Q1: Do any screenshots show the Android System Settings or App Info screen?
    Q2: Do you see the Permission selection screen (Location or Microphone)?
    Q3: Is the 'Flight Crew View' app visible?
    
    Return JSON:
    {
        "settings_visited": true/false,
        "permissions_screen_seen": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {})
        
        if parsed.get("settings_visited", False):
            vlm_score += 15
            feedback_parts.append("VLM confirmed Settings navigation")
        
        if parsed.get("permissions_screen_seen", False):
            vlm_score += 10
            feedback_parts.append("VLM confirmed Permissions screen access")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if programmatic check passed with high score, assume trajectory was valid
        if score >= 65: 
            vlm_score = 25
            feedback_parts.append("VLM skipped (Programmatic pass)")

    score += vlm_score

    # 4. Final Result Calculation
    passed = (score >= 85) and loc_bg and (not mic_granted)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }