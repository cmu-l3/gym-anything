#!/usr/bin/env python3
"""
Verifier for grant_quiz_accommodations task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quiz_accommodations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Target Values
    base_time_limit = str(metadata.get('base_time_limit_sec', 3600))
    base_attempts = str(metadata.get('base_attempts', 1))
    
    alice_time_limit = str(metadata.get('alice_time_limit_sec', 5400))
    bob_time_limit = str(metadata.get('bob_time_limit_sec', 7200))
    bob_attempts = str(metadata.get('bob_attempts', 2))

    # Read the exported JSON
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

    quiz = result.get('quiz', {})
    overrides = result.get('overrides', {})
    alice = overrides.get('alice', {})
    bob = overrides.get('bob', {})

    feedback = []
    score = 0

    # CRITICAL CHECK: Base settings preserved
    q_time = str(quiz.get('base_timelimit', ''))
    q_attempts = str(quiz.get('base_attempts', ''))
    
    if q_time != base_time_limit or q_attempts != base_attempts:
        feedback.append(f"CRITICAL FAILURE: Base quiz settings were modified. Expected {base_time_limit}s/1 attempt, found {q_time}s/{q_attempts} attempts.")
        # If the agent modifies the base quiz instead of overrides, they fail the task immediately.
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    else:
        feedback.append("Base settings preserved correctly.")

    # Alice Override Checks (40 points possible)
    if alice.get('found'):
        score += 15
        feedback.append("Alice override found.")
        
        if str(alice.get('timelimit', '')) == alice_time_limit:
            score += 25
            feedback.append("Alice time limit correct (90 mins).")
        else:
            feedback.append(f"Alice time limit incorrect: {alice.get('timelimit')}")
            
        # Verify attempts weren't inadvertently modified
        a_att = str(alice.get('attempts', ''))
        if a_att not in ['NULL', 'null', 'None', '', base_attempts]:
            feedback.append(f"Warning: Alice's attempts were unexpectedly modified to {a_att}.")
    else:
        feedback.append("Alice override NOT found.")

    # Bob Override Checks (60 points possible)
    if bob.get('found'):
        score += 15
        feedback.append("Bob override found.")
        
        if str(bob.get('timelimit', '')) == bob_time_limit:
            score += 25
            feedback.append("Bob time limit correct (120 mins).")
        else:
            feedback.append(f"Bob time limit incorrect: {bob.get('timelimit')}")
            
        if str(bob.get('attempts', '')) == bob_attempts:
            score += 20
            feedback.append("Bob attempts correct (2).")
        else:
            feedback.append(f"Bob attempts incorrect: {bob.get('attempts')}")
    else:
        feedback.append("Bob override NOT found.")

    # Optional VLM verification (for trajectory progression check)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = "These are screenshots from an agent configuring Moodle. Does any screenshot show the 'User overrides' screen for a quiz? Answer only 'yes' or 'no'."
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and "yes" in vlm_res.get("text", "").lower():
                feedback.append("VLM confirmed interaction with User overrides UI.")
            else:
                feedback.append("VLM did not detect the User overrides screen, but database verified.")
    except Exception as e:
        logger.info(f"VLM check skipped or failed: {e}")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }