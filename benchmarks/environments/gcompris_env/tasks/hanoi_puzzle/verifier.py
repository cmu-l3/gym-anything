#!/usr/bin/env python3
"""
Verifier for Tower of Hanoi task in GCompris.

Verification Strategy:
1. Programmatic: Check if app was running and if config/data files were modified (activity evidence).
2. VLM (Primary): Analyze trajectory frames to verify:
   - Navigation to the correct activity.
   - Manipulation of discs (puzzle state changes).
   - Successful completion (all discs on right peg).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hanoi_puzzle(traj, env_info, task_info):
    """
    Verify the agent solved the Tower of Hanoi puzzle.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 2. Basic Checks (10 points)
    if result_data.get("app_running", False):
        score += 5
        feedback_parts.append("App was running.")
    
    if result_data.get("files_modified", False):
        score += 5
        feedback_parts.append("Data/Config files modified (activity detected).")

    # 3. VLM Trajectory Verification (90 points)
    # We need to see the progression: Menu -> Hanoi Board -> Discs Moving -> Solved
    
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    # Combine frames for analysis
    # We ask the VLM to analyze the story told by these frames
    
    prompt = """
    You are verifying if an agent successfully solved the 'Tower of Hanoi' puzzle in the GCompris educational software.
    
    Please analyze these screenshots, which are ordered chronologically from the start to the end of the task.
    
    Look for the following stages:
    1. **Navigation**: Did the agent navigate from the main menu to the Tower of Hanoi activity? (Look for an icon with 3 pegs and discs, or the board itself appearing).
    2. **Activity Found**: Is the Tower of Hanoi board visible? (Three vertical pegs with colored discs).
    3. **Gameplay**: Do the discs change positions across the frames? (Evidence of moving discs).
    4. **Completion**: In the FINAL frames, are all the discs stacked on the RIGHTMOST peg? Or do you see a 'Congratulations' / 'Bonus' animation (often a flower, penguin, or smiley)?
    
    Scoring Criteria:
    - **Activity Found**: The Hanoi board is visible in at least one frame.
    - **Progress Made**: The discs are in different positions in later frames compared to earlier ones.
    - **Puzzle Solved**: The final state shows all discs on the rightmost peg OR a victory screen.
    
    Return a JSON object with:
    {
        "activity_found": true/false,
        "progress_made": true/false,
        "puzzle_solved": true/false,
        "reasoning": "Description of what you observed"
    }
    """
    
    vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
    
    if not vlm_response.get("success"):
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"VLM verification failed: {vlm_response.get('error')}"
        }
        
    analysis = vlm_response.get("parsed", {})
    logger.info(f"VLM Analysis: {analysis}")
    
    # Scoring based on VLM
    if analysis.get("activity_found", False):
        score += 20
        feedback_parts.append("VLM: Tower of Hanoi activity found.")
    else:
        feedback_parts.append("VLM: Could not confirm activity was found.")

    if analysis.get("progress_made", False):
        score += 30
        feedback_parts.append("VLM: Detected disc movement/gameplay.")
    else:
        feedback_parts.append("VLM: No significant progress/disc movement detected.")

    if analysis.get("puzzle_solved", False):
        score += 40
        feedback_parts.append("VLM: Puzzle solved successfully.")
    else:
        feedback_parts.append("VLM: Puzzle completion not verified.")

    # Final Feedback
    feedback = " ".join(feedback_parts)
    if analysis.get("reasoning"):
        feedback += f" (Reasoning: {analysis['reasoning']})"

    passed = score >= 60 and analysis.get("activity_found")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }