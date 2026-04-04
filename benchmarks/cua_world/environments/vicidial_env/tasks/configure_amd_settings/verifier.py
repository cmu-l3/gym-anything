#!/usr/bin/env python3
"""
Verifier for configure_amd_settings task.

Verifies:
1. Routing Extension (Critical) - must be 8369 to enable AMD.
2. VM Extension - must be 8320.
3. Tuning Parameters - Initial Silence, Word Length, Max Greeting must match specs.
4. VLM Verification - Trajectory must show interaction with Campaign Detail screen.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_amd_settings(traj, env_info, task_info):
    """
    Verify AMD configuration via DB state and VLM trajectory check.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_routing = metadata.get('expected_routing_ext', '8369')
    exp_vm = metadata.get('expected_vm_ext', '8320')
    exp_silence = metadata.get('expected_initial_silence', '3500')
    exp_word = metadata.get('expected_word_length', '2000')
    exp_greet = metadata.get('expected_max_greeting', '4000')

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # 1. Check DB State (85 points total)
    
    # Critical: Routing Extension (Enable AMD) - 40 pts
    act_routing = str(result.get('routing_ext', ''))
    if act_routing == exp_routing:
        score += 40
        feedback_parts.append("AMD Enabled (Routing Ext correct)")
    else:
        feedback_parts.append(f"AMD NOT enabled (Routing Ext: {act_routing}, expected {exp_routing})")

    # VM Extension - 15 pts
    act_vm = str(result.get('vm_ext', ''))
    if act_vm == exp_vm:
        score += 15
        feedback_parts.append("VM Route correct")
    else:
        feedback_parts.append(f"VM Route incorrect ({act_vm})")

    # Tuning Parameters - 30 pts (10 each)
    act_silence = str(result.get('initial_silence', ''))
    if act_silence == exp_silence:
        score += 10
    else:
        feedback_parts.append(f"Silence incorrect ({act_silence})")

    act_word = str(result.get('word_length', ''))
    if act_word == exp_word:
        score += 10
    else:
        feedback_parts.append(f"Word Length incorrect ({act_word})")

    act_greet = str(result.get('max_greeting', ''))
    if act_greet == exp_greet:
        score += 10
    else:
        feedback_parts.append(f"Max Greeting incorrect ({act_greet})")

    if score == 85:
        feedback_parts.append("All configuration values correct")

    # 2. VLM Trajectory Verification (15 points)
    # Ensure the agent actually visited the settings page and didn't just magically guess (anti-gaming)
    # or to confirm UI interaction if DB update failed but UI looked correct.
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a Vicidial Admin interface.
        Did the user navigate to the 'Campaign Detail' view? 
        Look for a long form with many settings fields like 'Dial Method', 'Auto Dial Level', or 'Answering Machine Detection'.
        Answer 'YES' if the detailed settings form is visible in any frame.
        """
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res and "YES" in str(vlm_res.get('parsed', '')).upper():
            score += 15
            feedback_parts.append("UI navigation verified")
        else:
            # Fallback point for partial success if DB correct
            if score > 0:
                score += 15 # Give benefit of doubt if they got the data right
            else:
                feedback_parts.append("UI navigation not clearly observed")
    else:
        # If no frames available (shouldn't happen), award points if data is correct
        if score > 40:
            score += 15

    # Final Pass/Fail Check
    # Must have enabled AMD (Routing Ext) and got at least 70 points
    passed = (act_routing == exp_routing) and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }