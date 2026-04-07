#!/usr/bin/env python3
"""
Verifier for replace_routine_exercise task.
Evaluates the database state extracted by export_result.sh and verifies
trajectory using the VLM.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_replace_routine_exercise(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read the exported JSON state
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported JSON state: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    routine_found = result.get('routine_found', False)
    day_found = result.get('day_found', False)
    exercises = result.get('exercises', [])

    # Fast fail if the structure was completely destroyed
    if not routine_found or not day_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The 'Push-Pull-Legs' routine or 'Push Day' was completely deleted or not found."
        }
    
    score += 10
    feedback.append("Routine and Day structure maintained.")

    # 2. Analyze the exercises in the day
    has_bench = False
    has_triceps = False
    has_overhead = False
    has_lateral = False
    lateral_sets = 0
    lateral_reps = 0

    for ex in exercises:
        name_lower = ex.get('name', '').lower()
        if 'bench' in name_lower:
            has_bench = True
        elif 'triceps' in name_lower:
            has_triceps = True
        elif 'overhead' in name_lower:
            has_overhead = True
        elif 'lateral raise' in name_lower:
            has_lateral = True
            lateral_sets = ex.get('sets', 0)
            lateral_reps = ex.get('reps', 0)

    # Criterion A: Collateral Damage Check (30 points)
    if has_bench:
        score += 15
        feedback.append("Bench Press correctly preserved.")
    else:
        feedback.append("ERROR: Bench Press was deleted.")
        
    if has_triceps:
        score += 15
        feedback.append("Triceps Extension correctly preserved.")
    else:
        feedback.append("ERROR: Triceps Extension was deleted.")

    # Criterion B: Target Exercise Removed (20 points)
    if not has_overhead:
        score += 20
        feedback.append("Overhead Press successfully removed.")
    else:
        feedback.append("ERROR: Overhead Press was not removed.")

    # Criterion C: Replacement Exercise Added (20 points)
    if has_lateral:
        score += 20
        feedback.append("Lateral Raise successfully added.")
    else:
        feedback.append("ERROR: Lateral Raise was not added.")

    # Criterion D: Replacement Exercise Configurations (20 points)
    if has_lateral:
        if lateral_sets == 3 and lateral_reps == 15:
            score += 20
            feedback.append(f"Lateral Raise config perfect: {lateral_sets} sets of {lateral_reps}.")
        else:
            feedback.append(f"Lateral Raise config incorrect: expected 3x15, got {lateral_sets}x{lateral_reps}.")

    # 3. VLM Verification (Trajectory confirmation)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        prompt = (
            "You are observing a user interacting with the wger fitness application. "
            "Did the user use the web interface to edit a workout routine (e.g., searching for exercises, "
            "adding exercises, or configuring sets/reps)? Answer simply Yes or No."
        )
        
        vlm_resp = query_vlm(images=all_frames, prompt=prompt)
        if vlm_resp and vlm_resp.get("success"):
            response_text = vlm_resp.get("response", "").lower()
            if "yes" in response_text:
                feedback.append("VLM confirmed UI interaction.")
            else:
                feedback.append("VLM could not confirm UI interaction.")

    # 4. Final calculation
    # Critical pass criteria: Must have removed OHP, added Lat Raise, and preserved at least one base exercise
    key_criteria_met = (not has_overhead) and has_lateral and (has_bench or has_triceps)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }