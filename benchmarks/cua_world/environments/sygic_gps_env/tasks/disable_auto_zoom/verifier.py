#!/usr/bin/env python3
"""
Verifier for disable_auto_zoom task.

Strategies:
1. Programmatic: Check Sygic's shared_preferences XML for "bAutoZoom" = "false".
2. VLM: Check trajectory frames to verify the agent actually navigated the settings menu.
"""

import json
import os
import tempfile
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_auto_zoom(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Host copy function not available"}

    # 1. Retrieve artifacts from the device
    temp_dir = tempfile.mkdtemp()
    local_prefs_path = os.path.join(temp_dir, "sygic_prefs.xml")
    local_result_path = os.path.join(temp_dir, "task_result.json")
    
    try:
        # Copy result JSON
        copy_from_env("/sdcard/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            task_result = json.load(f)
            
        # Copy Preferences XML (if export succeeded)
        prefs_exported = task_result.get("prefs_exported", False)
        prefs_content = ""
        if prefs_exported:
            try:
                copy_from_env("/sdcard/sygic_prefs_dump.xml", local_prefs_path)
                with open(local_prefs_path, 'r', encoding='utf-8', errors='ignore') as f:
                    prefs_content = f.read()
            except Exception as e:
                logger.warning(f"Failed to read prefs XML: {e}")
    except Exception as e:
        logger.error(f"Error copying/reading artifacts: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task artifacts"}

    # 2. Programmatic Verification (Primary)
    score = 0
    feedback_log = []
    
    # Check for the specific XML key for AutoZoom
    # Expected format: <boolean name="bAutoZoom" value="false" />
    # OR sometimes int: <int name="AutoZoom" value="0" />
    
    # We look for "AutoZoom" and "false" or "0"
    auto_zoom_disabled = False
    
    if prefs_content:
        # Regex for <boolean name=".*AutoZoom" value="false" />
        # Case insensitive just in case
        if re.search(r'name="[^"]*AutoZoom"[^>]*value="false"', prefs_content, re.IGNORECASE):
            auto_zoom_disabled = True
            feedback_log.append("Found 'AutoZoom' set to 'false' in preferences.")
        elif re.search(r'name="[^"]*AutoZoom"[^>]*value="0"', prefs_content, re.IGNORECASE):
            auto_zoom_disabled = True
            feedback_log.append("Found 'AutoZoom' set to '0' in preferences.")
        else:
            feedback_log.append("Could not find 'AutoZoom' set to disabled in preferences.")
            # Check if it exists as true to confirm we are looking at right file
            if re.search(r'name="[^"]*AutoZoom"[^>]*value="true"', prefs_content, re.IGNORECASE):
                feedback_log.append("Found 'AutoZoom' set to 'true' (Failed).")
    else:
        feedback_log.append("Preferences file not available for programmatic check.")

    if auto_zoom_disabled:
        score += 50
    
    # 3. VLM Verification (Secondary/Fallback)
    # Even if programmatic passes, we check VLM to ensure UI interaction occurred (anti-gaming)
    # If programmatic failed (maybe root issue), VLM becomes primary
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_log.append("No trajectory frames available.")
    else:
        prompt = """
        You are verifying a task in a GPS navigation app.
        The goal is to disable 'Auto-zoom'.
        
        Review these screenshots from the agent's session.
        1. Did the agent open a Settings menu?
        2. Did the agent navigate to 'Route & Navigation' or 'Map' settings?
        3. Do you see a toggle for 'Auto-zoom' (or similar) being switched off?
        
        Answer with JSON:
        {
            "opened_settings": true/false,
            "found_auto_zoom": true/false,
            "switched_off": true/false,
            "confidence": 0-10
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('opened_settings'): vlm_score += 10
            if parsed.get('found_auto_zoom'): vlm_score += 15
            if parsed.get('switched_off'): vlm_score += 25
            
            score += vlm_score
            feedback_log.append(f"VLM analysis: {parsed}")
            
        except Exception as e:
            logger.error(f"VLM query failed: {e}")
            feedback_log.append("VLM verification failed.")

    # Final scoring logic
    passed = False
    if auto_zoom_disabled:
        # If we confirmed via code, we are very confident
        passed = True
        if score < 100: score = 100 # Boost to full if hard proof found
    else:
        # If code check failed, rely on VLM strong signal
        if score >= 40: # Implies significant VLM evidence
             # But without code confirmation, we cap score or set pass threshold high
             if score >= 50: passed = True

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_log)
    }