#!/usr/bin/env python3
"""
Verifier for configure_user_profile_signature task.

VERIFICATION STRATEGY:
1. Programmatic DB Verification: Checks user profile updates (Title, Dept, Phone)
2. Programmatic Pref Verification: Checks deserialized user preferences (date/time format)
3. Programmatic Signature Verification: Checks signature table for exact text content and <img> tag
4. Trajectory Verification: Uses VLM to ensure actual GUI interaction with the WYSIWYG editor occurred.
"""

import os
import json
import tempfile
import logging
import re
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_user_profile(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Customer Service Representative")
    expected_dept = metadata.get('expected_department', "Global Support")
    expected_phone = metadata.get('expected_phone', "(555) 019-9283")
    expected_date_format = metadata.get('expected_date_format', "Y-m-d")
    expected_time_format = metadata.get('expected_time_format', "H:i")

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = result.get('task_start_time', 0)
    data = result.get('suitecrm_data', {})
    
    user_data = data.get('user', {})
    prefs_data = data.get('prefs', {})
    sig_data = data.get('signature', {})

    score = 0
    feedback_parts = []

    # 1. Profile Details (20 points)
    profile_score = 0
    if user_data.get('title') == expected_title:
        profile_score += 7
    if user_data.get('department') == expected_dept:
        profile_score += 7
    if user_data.get('phone_work') == expected_phone:
        profile_score += 6
    
    score += profile_score
    if profile_score == 20:
        feedback_parts.append("Profile fields updated correctly")
    elif profile_score > 0:
        feedback_parts.append("Profile fields partially updated")
    else:
        feedback_parts.append("Profile fields not updated")

    # 2. Regional Preferences (20 points)
    pref_score = 0
    if prefs_data.get('datef') == expected_date_format:
        pref_score += 10
    if prefs_data.get('timef') == expected_time_format:
        pref_score += 10
    
    score += pref_score
    if pref_score == 20:
        feedback_parts.append("Date/Time formats updated correctly")
    elif pref_score > 0:
        feedback_parts.append("Date/Time formats partially updated")
    else:
        feedback_parts.append("Date/Time formats not updated")

    # 3. Signature Validation (30 points)
    sig_score = 0
    if sig_data:
        sig_ctime = int(sig_data.get('ctime', 0))
        if sig_ctime >= task_start:  # Anti-gaming: Ensure it was created DURING this task
            sig_html = sig_data.get('signature_html', '')
            
            # Check text presence (15 points)
            has_title = expected_title.lower() in sig_html.lower()
            has_dept = expected_dept.lower() in sig_html.lower()
            if has_title and has_dept:
                sig_score += 15
                feedback_parts.append("Signature text correct")
            else:
                feedback_parts.append("Signature text missing required elements")
                
            # Check image presence (15 points)
            if re.search(r'<img[^>]+src=[\'"]([^\'"]+)[\'"][^>]*>', sig_html, re.IGNORECASE):
                sig_score += 15
                feedback_parts.append("Signature contains an image tag")
            else:
                feedback_parts.append("Signature is missing the uploaded image")
        else:
            feedback_parts.append("Signature found but created before task started (Anti-gaming triggered)")
    else:
        feedback_parts.append("Email signature 'Support Standard' not found")
        
    score += sig_score

    # 4. VLM Trajectory Verification (30 points)
    # Proves the agent actually used the UI to interact with the WYSIWYG editor
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = """
    You are evaluating a UI automation agent working in SuiteCRM.
    The agent was tasked with:
    1. Updating the user's profile details
    2. Modifying Date/Time preferences
    3. Creating an email signature using the WYSIWYG editor and inserting an image
    
    Analyze the trajectory frames. Do you see evidence that the agent navigated the User Profile settings, the Advanced tab (for date/time), and specifically interacted with an email signature WYSIWYG editor (the text box with formatting controls)?
    
    Respond in strict JSON:
    {
      "profile_navigated": true/false,
      "wysiwyg_interacted": true/false
    }
    """
    
    try:
        vlm_res = query_vlm(images=all_frames, prompt=vlm_prompt)
        vlm_parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if vlm_parsed.get('profile_navigated', False):
            vlm_score += 10
        if vlm_parsed.get('wysiwyg_interacted', False):
            vlm_score += 20
            
        score += vlm_score
        
        if vlm_score == 30:
            feedback_parts.append("VLM verified visual trajectory")
        else:
            feedback_parts.append("VLM did not verify all visual interactions")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Graceful degradation if VLM fails but programmatic passes perfectly
        if score == 70:
            score += 30
            feedback_parts.append("VLM failed but programmatic checks perfect (awarding full points)")

    # Final determination
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }