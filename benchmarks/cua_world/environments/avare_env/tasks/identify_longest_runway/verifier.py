#!/usr/bin/env python3
"""
Verifier for identify_longest_runway task.

Checks:
1. Output file exists and was created during task.
2. File content correctly identifies the longest runway (10L/28R).
3. File content correctly identifies length (~11870 ft).
4. VLM verifies the agent actually looked at the runway info screen.
"""

import json
import re
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_longest_runway(traj, env_info, task_info):
    """
    Verify that the agent identified the correct longest runway at KSFO.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_runways = metadata.get('expected_runways', ["10L", "28R"])
    expected_length = metadata.get('expected_length', 11870)
    tolerance = metadata.get('length_tolerance', 100)

    # 1. Retrieve Result JSON from Environment
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence (10 pts)
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file /sdcard/longest_runway.txt not created"}
    
    score += 10
    feedback_parts.append("File created")

    # 3. Check Anti-Gaming (Created during task) (10 pts)
    if result.get('created_during_task', False):
        score += 10
    else:
        feedback_parts.append("Warning: File timestamp check failed or ambiguous")

    # 4. Parse Content
    content = result.get('file_content', "")
    logger.info(f"Agent content: {content}")

    # Regex to find ID and Length
    # Looking for "Runway: 10L" or similar
    runway_match = re.search(r"Runway:\s*([\w/]+)", content, re.IGNORECASE)
    length_match = re.search(r"Length:\s*([\d,]+)", content, re.IGNORECASE)

    # Verify ID (40 pts)
    runway_correct = False
    if runway_match:
        found_id = runway_match.group(1).strip().upper()
        # Check against expected list (handle slashes like 10L/28R)
        for expected in expected_runways:
            if expected in found_id or found_id in expected:
                runway_correct = True
                break
        
        if runway_correct:
            score += 40
            feedback_parts.append(f"Correct runway ID: {found_id}")
        else:
            feedback_parts.append(f"Incorrect runway ID: {found_id}")
    else:
        feedback_parts.append("Could not parse Runway ID")

    # Verify Length (30 pts)
    length_correct = False
    if length_match:
        # Remove commas
        raw_length = length_match.group(1).replace(',', '')
        try:
            found_length = float(raw_length)
            if abs(found_length - expected_length) <= tolerance:
                length_correct = True
                score += 30
                feedback_parts.append(f"Correct length: {found_length}")
            else:
                feedback_parts.append(f"Length out of range: {found_length} (Expected {expected_length} +/- {tolerance})")
        except ValueError:
            feedback_parts.append("Invalid length format")
    else:
        feedback_parts.append("Could not parse Length")

    # 5. VLM Trajectory Verification (10 pts)
    # Check if they actually looked at the runway list
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying an agent using an aviation app.
    Look at these screenshots.
    1. Did the agent search for 'KSFO' or San Francisco Intl?
    2. Did the agent navigate to an 'Airport' information screen?
    3. Did the agent view a list of 'Runways' with their lengths?
    
    Answer JSON: {"searched_ksfo": bool, "viewed_runways": bool}
    """
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_resp.get('parsed', {})
        if parsed.get('searched_ksfo', False):
            vlm_score += 5
        if parsed.get('viewed_runways', False):
            vlm_score += 5
        
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append("Visual verification passed")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails, don't penalize provided programmatic is good
        if runway_correct and length_correct:
            score += 10

    passed = (runway_correct and length_correct and score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }