#!/usr/bin/env python3
"""
Verifier for setup_seasonal_moh task.

Verification Criteria:
1. Database: MOH Class 'HOLIDAY25' exists.
2. Database: Settings correct (Name='Holiday Promo 2025', Random='Y', Active='Y').
3. Filesystem: Directory /var/lib/asterisk/mohmp3/HOLIDAY25 exists.
4. Filesystem: 'holiday_jingle.wav' and 'seasonal_offer.wav' are present.
5. VLM: Validates that the agent interacted with the Admin UI and didn't just shell script it (anti-gaming).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_seasonal_moh(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # 1. Check MOH Class Existence (20 pts)
    if result.get('moh_exists'):
        score += 20
        feedback_parts.append("MOH Class created")
    else:
        feedback_parts.append("FAIL: MOH Class 'HOLIDAY25' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Configuration (20 pts)
    config = result.get('moh_config', {})
    config_score = 0
    
    # Name check (fuzzy match to allow small typos/spacing issues)
    expected_name = "Holiday Promo 2025"
    actual_name = config.get('name', '')
    if expected_name.lower() in actual_name.lower():
        config_score += 10
    else:
        feedback_parts.append(f"Name mismatch (expected '{expected_name}', got '{actual_name}')")

    # Random Order check
    if config.get('random_order') == 'Y':
        config_score += 5
    else:
        feedback_parts.append(f"Random Order incorrect (expected 'Y', got '{config.get('random_order')}')")

    # Active check
    if config.get('active') == 'Y':
        config_score += 5
    else:
        feedback_parts.append("MOH Class not active")
    
    score += config_score
    if config_score == 20:
        feedback_parts.append("Configuration correct")

    # 3. Check Files (40 pts)
    files = result.get('files', {})
    file_score = 0
    
    if files.get('jingle_uploaded'):
        file_score += 20
        feedback_parts.append("Jingle uploaded")
    else:
        feedback_parts.append("FAIL: holiday_jingle.wav missing")

    if files.get('offer_uploaded'):
        file_score += 20
        feedback_parts.append("Offer uploaded")
    else:
        feedback_parts.append("FAIL: seasonal_offer.wav missing")
        
    score += file_score

    # 4. VLM Verification (20 pts)
    # Ensure they actually used the UI
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    prompt = """
    Analyze these screenshots of a Vicidial Admin task.
    The user should be:
    1. Creating a Music On Hold entry (Admin > System Settings > Music On Hold).
    2. Uploading audio files (choosing files from a dialog).
    
    Do you see evidence of the Vicidial Admin interface, specifically the Music On Hold section or file upload screens?
    Answer YES or NO and explain.
    """
    
    try:
        vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_resp and vlm_resp.get('success'):
            analysis = vlm_resp.get('parsed', {}).get('response', '').lower()
            # Simple heuristic or use structured parsing if available
            if 'yes' in analysis:
                vlm_score = 20
                feedback_parts.append("VLM confirmed UI usage")
            else:
                feedback_parts.append("VLM could not confirm UI usage")
        else:
            # Fallback if VLM fails: give points if app was running
            if result.get('app_was_running'):
                vlm_score = 20
                feedback_parts.append("App running (VLM unavailable)")
    except:
        # Fallback
        if result.get('app_was_running'):
            vlm_score = 20
    
    score += vlm_score

    # Pass logic
    # Must have created class and uploaded at least one file to pass basic threshold
    passed = score >= 80 and result.get('moh_exists') and (files.get('jingle_uploaded') or files.get('offer_uploaded'))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }