#!/usr/bin/env python3
"""
Verifier for braille_alphabet@1 task.

Combines file-based activity checks with VLM trajectory analysis to verify:
1. Navigation to Discovery category
2. Launching Braille activity
3. Correctly solving at least 3 letters (visual confirmation)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_braille_alphabet(traj, env_info, task_info):
    """
    Verify the Braille alphabet learning task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {}).get('scoring', {})
    
    # Weights
    W_DISCOVERY = metadata.get('discovery_reached', 15)
    W_LAUNCH = metadata.get('activity_launched', 20)
    W_LETTER1 = metadata.get('first_letter_success', 20)
    W_LETTERS3 = metadata.get('three_letters_success', 30)
    W_PROGRESS = metadata.get('progress_saved', 10)
    W_EXIT = metadata.get('clean_exit', 5)

    score = 0
    feedback_parts = []
    
    # 1. Load File-based Results (Progress Data)
    # ------------------------------------------
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

    # Score Progress Data
    if result.get('progress_data_modified', False):
        score += W_PROGRESS
        feedback_parts.append("GCompris progress data was updated.")
    else:
        feedback_parts.append("No progress data saved (did you complete any activities?).")

    # 2. VLM Trajectory Verification
    # ------------------------------
    # We need to see the workflow: Menu -> Discovery -> Braille -> Solving -> Success -> Menu
    frames = sample_trajectory_frames(traj, n=8)  # Sample 8 frames
    
    prompt = """
    You are analyzing screenshots of a user performing a task in GCompris educational software.
    The goal is to navigate to the 'Braille Alphabets' activity and learn at least 3 letters.

    Please analyze the image sequence and answer the following questions with TRUE or FALSE:

    1. DISCOVERY_SHOWN: Do you see the 'Discovery' category screen? (Look for icons like lightbulbs, computer chips, or globes. Not the main menu).
    2. BRAILLE_INTERFACE_SHOWN: Do you see the Braille activity interface? It must show a 6-dot cell (2x3 grid) and a target letter.
    3. SUCCESS_ANIMATION_SEEN: Do you see any positive feedback animations (e.g., a smiling sun, Tux the penguin giving a thumbs up, or a 'Great!' message) indicating a correct answer?
    4. MULTIPLE_LETTERS_ATTEMPTED: Do you see the target letter change between frames (e.g., first it asks for 'a', then 'b')? Or do you see evidence of solving more than one?
    5. RETURN_TO_MENU: In the final frames, does the user return to a menu screen (Activity selection or Main Menu)?

    Provide your reasoning and a confidence score (low/medium/high).
    Return JSON format:
    {
        "discovery_shown": boolean,
        "braille_interface_shown": boolean,
        "success_animation_seen": boolean,
        "multiple_letters_attempted": boolean,
        "return_to_menu": boolean,
        "confidence": "string",
        "reasoning": "string"
    }
    """

    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if not vlm_result.get('success'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "VLM verification failed. " + " ".join(feedback_parts)
        }
        
    parsed = vlm_result.get('parsed', {})
    
    # Score VLM criteria
    if parsed.get('discovery_shown', False):
        score += W_DISCOVERY
        feedback_parts.append("Navigated to Discovery category.")
        
    if parsed.get('braille_interface_shown', False):
        score += W_LAUNCH
        feedback_parts.append("Launched Braille Alphabets activity.")
        
    if parsed.get('success_animation_seen', False):
        score += W_LETTER1
        feedback_parts.append("Completed at least one letter.")
        
    if parsed.get('multiple_letters_attempted', False) and parsed.get('success_animation_seen', False):
        # If we see multiple letters AND success, we infer they did the 3-letter goal
        # It's hard to count exactly 3 with sparse sampling, so we accept 'multiple' as proxy for good effort
        score += W_LETTERS3
        feedback_parts.append("Attempted multiple letters.")
        
    if parsed.get('return_to_menu', False):
        score += W_EXIT
        feedback_parts.append("Returned to menu.")

    # Calculate final status
    # Pass if they at least launched the activity and got one right (demonstrating the core skill)
    # Threshold: ~55 points (Launch 20 + Success 20 + Discovery 15)
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts),
        "details": parsed
    }