#!/usr/bin/env python3
"""
Verifier for connect_dots_mystery task.

Verification Strategy:
1. File Evidence (30 pts): Checks if 'solved_dots.png' and 'object_id.txt' were created.
2. Content Consistency (10 pts): Checks if the text report is not empty.
3. VLM Trajectory (40 pts): Verifies the agent navigated correctly and clicked dots in order.
4. VLM Result (20 pts): Verifies the final screenshot shows a completed shape (not just dots).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_connect_dots_mystery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Evidence
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # Criteria 1: File Evidence (30 pts total)
    # ------------------------------------------------------------------
    if result.get("screenshot_created_during_task"):
        score += 15
        feedback.append("Screenshot saved correctly.")
    elif result.get("screenshot_exists"):
        score += 5
        feedback.append("Screenshot exists but timestamp is suspicious.")
    else:
        feedback.append("No screenshot found.")

    if result.get("text_created_during_task"):
        score += 15
        feedback.append("Object ID text file created.")
    elif result.get("text_file_exists"):
        score += 5
        feedback.append("Text file exists but timestamp is suspicious.")
    else:
        feedback.append("No object ID text file found.")

    # ------------------------------------------------------------------
    # Criteria 2: Content Check (10 pts)
    # ------------------------------------------------------------------
    text_content = result.get("text_content", "").strip()
    if len(text_content) > 3:
        score += 10
        feedback.append(f"Object identified as: '{text_content}'")
    else:
        feedback.append("Object ID text is empty or too short.")

    # ------------------------------------------------------------------
    # Criteria 3: VLM Trajectory Analysis (60 pts total)
    # ------------------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    # Prompt A: Workflow & Navigation (40 pts)
    workflow_prompt = """
    Analyze these screenshots of an agent using GCompris educational software.
    The goal is to navigate to 'Connect the Dots' and solve a puzzle.
    
    Look for this specific progression:
    1. Main Menu -> Math Category (Sheep/123 icon)
    2. Math -> Numeracy/Counting Category
    3. Numeracy -> Connect the Dots activity (icon with numbered points)
    4. Playing the game: Clicking numbers in sequence (1, 2, 3...) to draw lines.
    
    Did the agent successfully navigate to the activity and attempt to solve it?
    """
    
    vlm_nav = query_vlm(
        images=frames,
        prompt=workflow_prompt,
        options=["Navigation successful", "Wrong activity", "Stayed on menu"]
    )
    
    if vlm_nav and "Navigation successful" in vlm_nav.get("text", ""):
        score += 30
        feedback.append("VLM confirmed correct navigation and interaction.")
    else:
        feedback.append("VLM did not observe correct navigation/interaction.")

    # Prompt B: Completion Verification (20 pts)
    # We check the final frame to see if the puzzle is actually SOLVED (image revealed)
    completion_prompt = """
    Look at this final screenshot of the GCompris 'Connect the Dots' activity.
    
    Is the puzzle COMPLETED? 
    - Completed means the outline is fully closed, and often the shape is filled with color or replaced by a real drawing (the 'hidden picture' is revealed).
    - Incomplete means there are still loose dots or the shape is open.
    
    Also, does the text report provided by the agent match the image?
    Agent Report: "{}"
    
    Answer YES if the puzzle is visibly completed/solved.
    """.format(text_content)
    
    vlm_complete = query_vlm(
        image=final_frame,
        prompt=completion_prompt,
        options=["YES", "NO"]
    )
    
    if vlm_complete and "YES" in vlm_complete.get("text", ""):
        score += 30
        feedback.append("VLM confirmed puzzle completion (image revealed).")
    else:
        feedback.append("VLM did not see a completed puzzle state.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    # Pass threshold: 70 points
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }