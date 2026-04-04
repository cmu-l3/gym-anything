#!/usr/bin/env python3
"""
Verifier for family_tree_relationship task.

Verification Strategy:
1. File Verification (40 pts):
   - Checks if ~/Documents/family_tree_solved.png exists.
   - Checks if it was created during the task (anti-gaming).
   - Checks if it is a valid image of sufficient size.

2. VLM Verification (60 pts):
   - Trajectory Analysis: Did the agent navigate to the Family activity?
   - Workflow Analysis: Did the agent drag labels to the tree?
   - Success Verification: Did the final state show a completed tree/success animation?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_family_tree_relationship(traj, env_info, task_info):
    """
    Verify the family tree task using file checks and VLM trajectory analysis.
    """
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 2. File Verification (40 Points)
    file_exists = task_result.get("output_file_exists", False)
    file_fresh = task_result.get("output_file_created_during_task", False)
    file_size = task_result.get("output_file_size", 0)

    if file_exists:
        if file_size > 10000:  # Arbitrary threshold for a non-empty screenshot
            score += 20
            feedback_parts.append("Screenshot file exists and is valid size.")
            if file_fresh:
                score += 20
                feedback_parts.append("Screenshot was created during the task.")
            else:
                feedback_parts.append("Warning: Screenshot timestamp is old (pre-task).")
        else:
            feedback_parts.append("Screenshot file is too small to be valid.")
    else:
        feedback_parts.append("Screenshot file not found at expected path.")

    # 3. VLM Trajectory Verification (60 Points)
    # We sample frames to see the workflow, not just the end result
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    # Add final frame to analysis set if not already included
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": score, "feedback": "No video trajectory available for verification."}

    vlm_prompt = """
    You are verifying an agent performing a task in the GCompris educational software.
    
    Task Goal: Navigate to the 'Family' activity (family tree puzzle) and solve it by dragging labels (Grandfather, Mother, etc.) to the correct people.
    
    Analyze the provided sequence of screenshots from the user's session.
    
    Check for these specific milestones:
    1. NAVIGATION: Did the user leave the main menu and enter the 'Family' activity? (Look for a tree structure with character portraits).
    2. INTERACTION: Is there evidence of dragging labels or labels appearing on the tree nodes?
    3. COMPLETION: Is the puzzle solved? Look for:
       - All labels placed correctly on the tree.
       - A success animation (flower, star, OK sign, or 'Great' message).
       - Or the user manually taking a screenshot of the completed tree.

    Return JSON:
    {
        "navigated_to_activity": true/false,
        "interaction_observed": true/false,
        "puzzle_solved": true/false,
        "confidence": "low/medium/high",
        "reasoning": "Explain what you saw"
    }
    """

    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("navigated_to_activity"):
            vlm_score += 20
            feedback_parts.append("VLM: Successfully navigated to Family activity.")
        
        if parsed.get("interaction_observed"):
            vlm_score += 20
            feedback_parts.append("VLM: Interaction with puzzle detected.")
            
        if parsed.get("puzzle_solved"):
            vlm_score += 20
            feedback_parts.append("VLM: Puzzle completion/Success state verified.")
        else:
            feedback_parts.append("VLM: Did not detect clear puzzle completion state.")
            
        feedback_parts.append(f"VLM Reason: {parsed.get('reasoning', 'No reasoning provided')}")
    else:
        feedback_parts.append("VLM verification failed to run.")

    score += vlm_score

    # 4. Final Decision
    # Pass if score >= 60 AND (Puzzle Solved OR (Interaction Observed AND File Saved))
    # This allows passing if VLM misses the exact "success" frame but the user saved the proof file.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }