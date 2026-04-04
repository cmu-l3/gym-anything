#!/usr/bin/env python3
"""
Verifier for add_wifi_text_badge task.

Verification Logic:
1. Primary: VLM trajectory analysis to verify:
   - Badge Designer was opened
   - Text "GuestNet" and "Visitor2025" was added to the canvas
   - Text is visible on the badge layout
2. Secondary: File system check to confirm templates/settings were saved (timestamp check).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_wifi_text_badge(traj, env_info, task_info):
    """
    Verifies that the agent added the specific Wi-Fi text to the badge template.
    """
    # 1. Setup and load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_ssid = metadata.get('expected_ssid', 'GuestNet')
    expected_pass = metadata.get('expected_pass', 'Visitor2025')
    
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract signals
    template_modified = task_result.get('template_modified', False)
    app_running = task_result.get('app_was_running', False)
    
    # 3. VLM Verification (Primary)
    # We look at trajectory frames because the final screen might be closed or obscured
    frames = sample_trajectory_frames(traj, n=6)
    final_shot = get_final_screenshot(traj)
    if final_shot:
        frames.append(final_shot)
        
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No video evidence available for verification"}

    prompt = f"""
    You are verifying a software task in Jolly Lobby Track where the user must edit a badge template.
    
    Goal: Add a text field with Wi-Fi details: "Wi-Fi: {expected_ssid} | Pass: {expected_pass}"
    
    Review these screenshots from the session and answer:
    1. Did the user open a Badge Designer or Template Editor window? (Look for a grid, ruler, or design canvas)
    2. Is the text "{expected_ssid}" visible on the badge design or in a text properties box?
    3. Is the text "{expected_pass}" visible on the badge design or in a text properties box?
    4. Did the user save the changes (clicked Save icon or File > Save)?
    
    Output JSON:
    {{
        "designer_opened": boolean,
        "ssid_text_visible": boolean,
        "pass_text_visible": boolean,
        "save_action_observed": boolean,
        "confidence": "low|medium|high"
    }}
    """
    
    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    if not vlm_response.get('success'):
        return {"passed": False, "score": 0, "feedback": "VLM analysis failed"}
        
    analysis = vlm_response.get('parsed', {})
    
    # 4. Scoring
    score = 0
    feedback = []
    
    # Criterion 1: Designer Opened (20 pts)
    if analysis.get('designer_opened'):
        score += 20
        feedback.append("Badge Designer accessed.")
    else:
        feedback.append("Failed to access Badge Designer.")
        
    # Criterion 2: Correct Text Content (50 pts)
    text_ok = False
    if analysis.get('ssid_text_visible'):
        score += 25
        feedback.append(f"SSID '{expected_ssid}' found.")
    
    if analysis.get('pass_text_visible'):
        score += 25
        feedback.append(f"Password '{expected_pass}' found.")
        
    if analysis.get('ssid_text_visible') and analysis.get('pass_text_visible'):
        text_ok = True

    # Criterion 3: Save / Persistence (30 pts)
    # Strongest signal is file modification, fallback to visual save
    saved = False
    if template_modified:
        score += 30
        saved = True
        feedback.append("Template file modification detected (Change saved).")
    elif analysis.get('save_action_observed'):
        score += 20 # Slightly less if we only saw it visually but no file change detected
        saved = True
        feedback.append("Save action observed visually.")
    else:
        feedback.append("No evidence that changes were saved.")

    # Pass logic
    # Must have entered correct text AND saved (or modified file)
    passed = text_ok and saved and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }