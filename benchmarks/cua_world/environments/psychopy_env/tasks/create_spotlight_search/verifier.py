#!/usr/bin/env python3
"""
Verifier for create_spotlight_search task.

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. Valid .psyexp file created (10 pts)
  2. Conditions file created and valid (10 pts)
  3. Image component exists (10 pts)
  4. Mouse component exists (10 pts)
  5. Aperture component exists (10 pts)
  6. Aperture position links to mouse (10 pts)
  7. Aperture updates "every frame" (10 pts)

VLM checks (30 points):
  8. Trajectory verification: Does the agent test the spotlight?
     - Look for runs where screen is mostly masked (dark/grey)
     - Look for visible region moving (spotlight effect)

Pass threshold: 75 points (Requires complete programmatic implementation OR significant partial + VLM proof of function)
"""

import json
import tempfile
import os
import logging
from vlm_utils import sample_trajectory_frames, query_vlm

logger = logging.getLogger(__name__)

def verify_create_spotlight_search(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    # 1. Load programmatic result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/create_spotlight_search_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 2. Check Nonce (Anti-gaming)
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        os.unlink(nonce_path)
        
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "FAIL: Nonce mismatch (anti-gaming)"}
    except:
        pass # If nonce file missing, rely on other checks

    # 3. Programmatic Scoring (70 pts)
    if result.get('file_exists') and result.get('is_valid_xml'):
        score += 10
        feedback_parts.append("Valid .psyexp file created")
    else:
        feedback_parts.append("No valid .psyexp file found")

    if result.get('conditions_file_valid'):
        score += 10
        feedback_parts.append("Valid conditions file linked")
    elif result.get('has_loop'):
        score += 5
        feedback_parts.append("Loop created but conditions file issue")

    if result.get('has_image'):
        score += 10
        feedback_parts.append("Image component present")
    
    if result.get('has_mouse'):
        score += 10
        feedback_parts.append("Mouse component present")
        
    if result.get('has_aperture'):
        score += 10
        feedback_parts.append("Aperture component present")
        
        # Critical Logic Checks
        if result.get('aperture_tracks_mouse'):
            score += 10
            feedback_parts.append("Aperture tracks mouse position")
        else:
            feedback_parts.append("Aperture NOT linked to mouse")
            
        if result.get('aperture_updates_frames'):
            score += 10
            feedback_parts.append("Aperture updates every frame")
        else:
            feedback_parts.append("Aperture update mode incorrect")
    else:
        feedback_parts.append("Missing Aperture component")

    # 4. VLM Verification (30 pts)
    # Check if we see the spotlight effect in trajectory
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying a PsychoPy 'spotlight' task.
    In this task, the screen should be mostly covered by a mask (Aperture), revealing the image only through a small window/circle.
    
    Look at the sequence of screenshots.
    1. Do you see the PsychoPy Builder interface (gray flow diagram)?
    2. Do you see a 'Run' attempt (a black or gray window filling the screen)?
    3. CRITICAL: In the run window, do you see a 'spotlight' effect? 
       - Most of the screen is blocked/masked.
       - A specific circular area reveals content (like letters 'L' or 'T').
       - Does this visible area appear in different positions in different frames (indicating it moves)?
       
    Respond in JSON:
    {
        "builder_visible": true,
        "run_window_visible": true,
        "spotlight_effect_visible": true,
        "mask_visible": true,
        "confidence": "high"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    vlm_score = 0
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('builder_visible'):
            vlm_score += 5
        if parsed.get('run_window_visible'):
            vlm_score += 5
        if parsed.get('spotlight_effect_visible') or parsed.get('mask_visible'):
            vlm_score += 20
            feedback_parts.append("VLM confirmed spotlight/mask effect")
        else:
            feedback_parts.append("VLM did not see spotlight effect")
    
    score += vlm_score

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }