#!/usr/bin/env python3
"""
Verifier for Prime Number Muncher task (GCompris).
Uses VLM trajectory analysis to verify gameplay and scoring.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prime_muncher(traj, env_info, task_info):
    """
    Verifies that the agent played Number Munchers and scored points by eating primes.
    """
    # 1. Setup and Basic Checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    app_running = task_result.get("app_running", False)
    
    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=6)
    final_shot = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available"}

    # Prepare VLM prompt
    prompt = """
    You are verifying an agent playing the 'Number Munchers' educational game in GCompris.
    
    The goal is to navigate to the game, eat Prime Numbers (2, 3, 5, 7, 11, etc.), and score points.
    
    Review the sequence of screenshots and the final screenshot.
    
    1. **Identify Activity**: Is the agent in the 'Number Munchers' (or similar grid-based math game) activity? It typically looks like a grid of numbers with a small creature.
    2. **Gameplay Progress**: Does the score increase? Or do numbers disappear from the grid indicating they were eaten?
    3. **Score Check**: Look at the final score (usually at the top of the screen). 
       - Estimate the score value.
       - Is it greater than 0?
       - Is it greater than or equal to 20?
    4. **Game Over**: Is the 'Game Over' or 'Congratulations' screen visible?
    
    Output JSON:
    {
        "is_number_munchers": true/false,
        "score_value": <number or -1 if not found>,
        "score_increased": true/false,
        "primes_eaten_evidence": true/false,
        "feedback": "string explaining observations"
    }
    """
    
    all_images = frames + [final_shot] if final_shot else frames
    vlm_resp = query_vlm(images=all_images, prompt=prompt)
    
    if not vlm_resp.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to run"}
        
    data = vlm_resp.get("parsed", {})
    logger.info(f"VLM Analysis: {data}")

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Activity Found (20 pts)
    if data.get("is_number_munchers"):
        score += 20
        feedback_parts.append("Found Number Munchers activity.")
    else:
        feedback_parts.append("Did not find Number Munchers activity.")
        
    # Criterion 2: Attempted Gameplay (10 pts)
    if app_running:
        score += 10 # Base points for keeping app open
    
    # Criterion 3: Score > 0 (30 pts)
    est_score = data.get("score_value", 0)
    score_increased = data.get("score_increased", False)
    primes_evidence = data.get("primes_eaten_evidence", False)
    
    gameplay_active = (est_score > 0) or score_increased or primes_evidence
    
    if gameplay_active:
        score += 30
        feedback_parts.append("Gameplay detected (score > 0).")
    else:
        feedback_parts.append("No evidence of scoring points.")

    # Criterion 4: Target Score >= 20 (30 pts)
    # We accept either explicit score reading or strong evidence of sustained gameplay
    if est_score >= 20:
        score += 30
        feedback_parts.append(f"Target score reached ({est_score}).")
    elif est_score >= 10:
        score += 15 # Partial credit
        feedback_parts.append(f"Partial score reached ({est_score}).")
    
    # Criterion 5: Survival/Completion (10 pts)
    # If they are still playing or reached game over with high score
    if gameplay_active and app_running:
        score += 10

    passed = (score >= 60) and data.get("is_number_munchers") and gameplay_active

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts) + f" (VLM: {data.get('feedback', '')})"
    }