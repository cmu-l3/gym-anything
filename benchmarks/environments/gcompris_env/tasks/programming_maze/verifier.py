#!/usr/bin/env python3
"""
Verifier for GCompris Programming Maze task.

Verification Strategy:
1. VLM Trajectory Analysis (Primary):
   - Verify agent navigated to correct activity
   - Verify blocks were placed (programming interaction)
   - Verify Tux moved (execution)
   - Verify visual progression from Level 1 to Level 2
2. File Verification (Secondary):
   - Check if requested screenshots exist and were created during task
3. App State:
   - Check if GCompris is running
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_programming_maze(traj, env_info, task_info):
    # 1. Setup and load export data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract file-based metrics
    l1_shot = task_result.get("level_1_screenshot", {})
    l2_shot = task_result.get("level_2_screenshot", {})
    app_running = task_result.get("app_running", False)

    score = 0
    feedback = []

    # Score File Evidence (20 pts)
    if l1_shot.get("exists") and l1_shot.get("valid_time"):
        score += 10
        feedback.append("Level 1 screenshot captured.")
    
    if l2_shot.get("exists") and l2_shot.get("valid_time"):
        score += 10
        feedback.append("Level 2 screenshot captured.")

    # Score App State (5 pts)
    if app_running:
        score += 5
        feedback.append("GCompris remained open.")

    # 3. VLM Trajectory Verification (75 pts)
    # We look at frames to verify the actual workflow
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available."}

    vlm_prompt = """
    Analyze these screenshots of a user interacting with GCompris educational software.
    The user task is to open "Programming Maze" and complete Level 1.
    
    Look for these specific milestones:
    1. **Navigation**: Did the user open the "Computer Discovery" category (monitor icon) and find the "Programming Maze" activity?
    2. **Interaction**: Did the user drag command blocks (arrows/instruction icons) into the program sequence area?
    3. **Execution**: Is there visual evidence of the character (Tux/Penguin) moving along a path?
    4. **Success/Progression**: Did the user finish the level or does the final state show a new maze layout (Level 2)?
    
    Respond in JSON format:
    {
        "activity_opened": true/false,
        "blocks_placed": true/false,
        "execution_attempted": true/false,
        "level_completed": true/false,
        "confidence": "high/medium/low",
        "reasoning": "brief explanation"
    }
    """
    
    try:
        # We append the final frame to ensure we capture the end state
        analysis_images = frames + [final_frame] if final_frame else frames
        vlm_response = query_vlm(images=analysis_images, prompt=vlm_prompt)
        
        if vlm_response and vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            logger.info(f"VLM Analysis: {parsed}")
            
            # Weighted scoring based on VLM
            if parsed.get("activity_opened"):
                score += 15
                feedback.append("VLM confirmed activity opened.")
            
            if parsed.get("blocks_placed"):
                score += 20
                feedback.append("VLM confirmed blocks placed.")
                
            if parsed.get("execution_attempted"):
                score += 20
                feedback.append("VLM confirmed program execution.")
                
            if parsed.get("level_completed"):
                score += 20
                feedback.append("VLM confirmed level completion.")
        else:
            feedback.append("VLM verification failed or returned invalid format.")
            
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback.append("Error during visual verification.")

    # 4. Final Assessment
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }