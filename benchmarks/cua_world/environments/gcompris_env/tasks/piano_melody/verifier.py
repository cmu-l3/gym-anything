#!/usr/bin/env python3
"""
Verifier for GCompris Piano Melody task.

Verification Strategy:
1. Programmatic:
   - Check if GCompris is running.
   - Check if result screenshot exists and was created during task.
2. VLM (Visual Language Model):
   - Workflow Analysis: Did agent navigate from menu -> category -> piano?
   - Content Analysis: Is the final screen the piano activity? Are notes visible on staff?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_piano_melody(traj, env_info, task_info):
    """
    Verify the agent played a melody on the GCompris piano.
    """
    # 1. Setup and retrieve data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load programmatic result
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Initialize Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: App State (10 pts)
    if task_result.get("app_running", False):
        score += 10
        feedback_parts.append("GCompris application is running.")
    else:
        feedback_parts.append("GCompris application was closed.")

    # Criterion 2: Screenshot Evidence (10 pts)
    # We give points if the agent saved the screenshot as requested
    if task_result.get("screenshot_created_during_task", False):
        score += 10
        feedback_parts.append("Agent successfully saved the result screenshot.")
    elif task_result.get("screenshot_exists", False):
        # Screenshot exists but might have been taken by export script fallback
        score += 5
        feedback_parts.append("Screenshot exists (fallback).")
    else:
        feedback_parts.append("No screenshot available.")

    # 3. VLM Verification
    # We need to verify: 
    # A) Navigation/Workflow (did they find it?)
    # B) Execution (did they play notes?)

    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Combine frames for the VLM to see the story
    # We use the final screen from the agent's output if available, otherwise the last frame
    
    # VLM Prompt
    prompt = """
    You are evaluating an agent using educational software (GCompris).
    The goal is: Navigate to the Piano/Music activity and play a C major scale (C-D-E-F-G).

    Review the sequence of images provided (trajectory frames + final state).
    
    Determine the following:
    1. Did the agent start at a main menu/category screen?
    2. Did the agent navigate to a music or piano activity? (Look for a piano keyboard interface).
    3. In the final states, are there notes visible on the musical staff or keys being pressed?
    4. Is the final screen showing the Piano Composition activity?
    
    Respond in JSON:
    {
        "started_at_menu": boolean,
        "found_piano_activity": boolean,
        "notes_played_visible": boolean,
        "correct_activity_final": boolean,
        "reasoning": "string explanation"
    }
    """

    vlm_response = query_vlm(
        images=frames + [final_screen],
        prompt=prompt
    )

    if vlm_response and vlm_response.get("success"):
        analysis = vlm_response.get("parsed", {})
        
        # Criterion 3: Navigation (30 pts)
        if analysis.get("started_at_menu") and analysis.get("found_piano_activity"):
            score += 30
            feedback_parts.append("Successfully navigated to Piano activity.")
        elif analysis.get("found_piano_activity"):
            score += 20
            feedback_parts.append("Found Piano activity, but start state unclear.")
        else:
            feedback_parts.append("Failed to navigate to the Piano activity.")

        # Criterion 4: Activity Correctness (20 pts)
        if analysis.get("correct_activity_final"):
            score += 20
            feedback_parts.append("Final screen shows correct Piano activity.")
        else:
            feedback_parts.append("Final screen is not the Piano activity.")

        # Criterion 5: Task Completion / Notes Played (30 pts)
        if analysis.get("notes_played_visible"):
            score += 30
            feedback_parts.append("Visible evidence of notes played on the staff/keyboard.")
        else:
            feedback_parts.append("No notes visible on the staff.")
            
        feedback_parts.append(f"VLM Reasoning: {analysis.get('reasoning', 'None')}")
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # 4. Final Verdict
    passed = score >= 60  # Require navigation + some activity interaction
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }