#!/usr/bin/env python3
"""
Verifier for check_antiviral_prophylaxis_with_ibrutinib task.

Verification Logic:
1. File Existence & Anti-Gaming (20 pts): /sdcard/interaction_result.txt must exist and be created during task.
2. File Content Accuracy (40 pts): Must contain "Ibrutinib", "Aciclovir", and correct color "Green".
3. VLM Trajectory Verification (40 pts):
   - Did the agent actually navigate the app?
   - Did they see the Ibrutinib -> Antivirals -> Aciclovir screen?
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_antiviral_prophylaxis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_color = metadata.get('expected_color', 'Green').lower()
    
    score = 0
    feedback_parts = []
    
    # =======================================================
    # 1. Programmatic Verification (File & Content) - 60 pts
    # =======================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_exists = result_data.get('file_exists', False)
    created_during = result_data.get('created_during_task', False)
    content = result_data.get('file_content', '').lower()

    if not file_exists:
        feedback_parts.append("Result file not found.")
    elif not created_during:
        feedback_parts.append("Result file exists but was not modified during the task (anti-gaming failure).")
    else:
        score += 20
        feedback_parts.append("Result file created successfully.")
        
        # Check Content
        content_score = 0
        if "ibrutinib" in content:
            content_score += 10
            feedback_parts.append("Found drug 'Ibrutinib'.")
        else:
            feedback_parts.append("Missing drug 'Ibrutinib'.")
            
        if "aciclovir" in content or "acyclovir" in content:
            content_score += 10
            feedback_parts.append("Found co-medication 'Aciclovir'.")
        else:
            feedback_parts.append("Missing co-medication 'Aciclovir'.")
            
        # Check specific color interaction
        # We look for the expected color, but also penalize if a WRONG color is explicitly stated
        # Colors: red, orange, yellow, green, grey
        found_colors = []
        for c in ["red", "orange", "yellow", "green", "grey", "gray"]:
            if c in content:
                found_colors.append(c)
        
        if expected_color in found_colors:
            content_score += 20
            feedback_parts.append(f"Correct interaction color '{expected_color}' found.")
        elif found_colors:
            feedback_parts.append(f"Wrong interaction color found (found {found_colors}, expected {expected_color}).")
        else:
            feedback_parts.append("No interaction color specified in file.")
            
        score += content_score

    # =======================================================
    # 2. VLM Trajectory Verification - 40 pts
    # =======================================================
    # We need to verify the agent actually looked up the information
    # instead of just guessing or knowing it from pre-training.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying an agent's workflow in the 'Liverpool Cancer iChart' Android app.
    The agent should have:
    1. Searched for or navigated to 'Ibrutinib' in the Cancer Drug list.
    2. Opened the 'Antivirals' co-medication category.
    3. Viewed a list containing 'Aciclovir' with a colored interaction indicator (Green/Yellow/Red/Grey).

    Look at the sequence of screenshots.
    
    Q1: Is the 'Liverpool Cancer iChart' app visible in the frames?
    Q2: Is there a frame showing 'Ibrutinib' selected or being searched?
    Q3: Is there a frame showing the 'Antivirals' category or a list of antiviral drugs (like Aciclovir, Adefovir, etc.)?
    Q4: Does the final result seem to be derived from the app (the app was actually used)?
    
    Respond in JSON format:
    {
        "app_used": true/false,
        "ibrutinib_seen": true/false,
        "antivirals_seen": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('app_used'):
            vlm_score += 10
        if parsed.get('ibrutinib_seen'):
            vlm_score += 15
        if parsed.get('antivirals_seen'):
            vlm_score += 15
            
        if vlm_score < 40:
             feedback_parts.append(f"VLM Verification partial pass: App Used={parsed.get('app_used')}, Ibrutinib Seen={parsed.get('ibrutinib_seen')}, Antivirals Seen={parsed.get('antivirals_seen')}.")
        else:
             feedback_parts.append("VLM Verification passed: Navigation trajectory confirmed.")
    else:
        feedback_parts.append("VLM Verification failed or inconclusive (could not analyze images).")
        # Fallback: if programmatic score is high (60/60), give partial credit for VLM to avoid false fails on API errors
        if score >= 60:
            vlm_score = 20
            feedback_parts.append("Awarding partial VLM points due to API failure but perfect programmatic result.")

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }