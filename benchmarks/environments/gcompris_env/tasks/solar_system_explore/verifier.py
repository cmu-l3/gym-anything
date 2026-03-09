#!/usr/bin/env python3
"""
Verifier for GCompris Solar System Explore task.

Multi-criteria verification:
1. File Creation (10 pts): Output file exists and was created during task.
2. Content Structure (10 pts): Exactly 8 lines.
3. Content Correctness (40 pts): Correct planet names in correct order.
4. Cleanliness (5 pts): No non-planets (Pluto).
5. Process Verification (35 pts): VLM confirms GCompris Solar System activity was opened.
"""

import json
import tempfile
import os
import base64
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_solar_system_explore(traj, env_info, task_info):
    """
    Verify the agent listed planets correctly and actually used GCompris.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_planets = metadata.get('expected_planets', [
        "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"
    ])
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. READ TASK RESULT
    # ================================================================
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
            
    # ================================================================
    # 2. FILE VERIFICATION (65 points total)
    # ================================================================
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    content_b64 = result.get('file_content_base64', "")
    
    # Criterion 1: File Exists & Anti-gaming (10 pts)
    if output_exists and created_during_task:
        score += 10
        feedback_parts.append("File created successfully")
    elif output_exists:
        score += 5
        feedback_parts.append("File exists but timestamp is old (did you overwrite it?)")
    else:
        feedback_parts.append("Output file not found")
        # Critical fail if no file
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # Decode content
    try:
        content = base64.b64decode(content_b64).decode('utf-8')
        lines = [line.strip() for line in content.splitlines() if line.strip()]
    except Exception:
        lines = []
        feedback_parts.append("File content decoding failed")

    # Criterion 2: Structure (10 pts)
    if len(lines) == 8:
        score += 10
        feedback_parts.append("Correct line count (8)")
    else:
        feedback_parts.append(f"Incorrect line count: {len(lines)} (expected 8)")

    # Criterion 3: Correct Names and Order (40 pts)
    # We check order directly. 
    # Partial credit: 5 pts for each correct planet in correct slot.
    correct_slots = 0
    for i in range(min(len(lines), len(expected_planets))):
        if lines[i].lower() == expected_planets[i].lower():
            correct_slots += 1
            
    # Scale 8 slots to 40 points (5 pts per planet)
    points_for_content = correct_slots * 5
    score += points_for_content
    
    if correct_slots == 8:
        feedback_parts.append("All planets correct and in order")
    else:
        feedback_parts.append(f"{correct_slots}/8 planets correct in order")

    # Criterion 4: Cleanliness (5 pts)
    # Check for Pluto or other common errors
    forbidden = metadata.get('forbidden_words', [])
    found_forbidden = [w for w in forbidden if any(w.lower() in l.lower() for l in lines)]
    if not found_forbidden:
        score += 5
    else:
        feedback_parts.append(f"Found extraneous entries: {', '.join(found_forbidden)}")

    # ================================================================
    # 3. VLM PROCESS VERIFICATION (35 points)
    # ================================================================
    # We need to verify they actually used the app, not just wrote the file from memory.
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an educational task in GCompris software.
    The user was supposed to:
    1. Navigate to the Solar System activity.
    2. Open the activity (which shows a visualization of the sun and planets).
    
    Look at these screenshots of the user's session.
    
    Question 1: Do you see the GCompris Solar System activity open in any frame? 
    (Look for a black background with a glowing Sun, orbital lines, and planets, usually with an information box on the side).
    
    Question 2: Do you see the user navigating the GCompris menus (clicking on icons)?
    
    Return JSON:
    {
        "solar_system_visible": true/false,
        "menu_navigation_visible": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_score = 0
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('solar_system_visible'):
            vlm_score += 25
            feedback_parts.append("VLM verified Solar System activity was opened")
        else:
            feedback_parts.append("VLM could NOT verify Solar System activity was opened")
            
        if parsed.get('menu_navigation_visible'):
            vlm_score += 10
            feedback_parts.append("VLM verified menu navigation")
    else:
        # Fallback if VLM fails: give partial credit if file is perfect
        if score >= 60:
            vlm_score = 15
            feedback_parts.append("VLM check failed, giving partial fallback credit")
            
    score += vlm_score

    # ================================================================
    # FINAL SCORING
    # ================================================================
    passed = (score >= 60) and (correct_slots >= 4) and output_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }