#!/usr/bin/env python3
"""
Verifier for GCompris Double Entry Table task.

Verification Strategy:
1. File Evidence (20%): Checks if the agent saved the required screenshot.
2. VLM Trajectory (80%): Analyzes video frames to verify:
   - Navigation to the correct activity.
   - Interaction with the grid (dragging items).
   - Successful completion of levels (feedback/animations).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_double_entry_table(traj, env_info, task_info):
    """
    Verify the agent completed the Double Entry Table activity levels.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result JSON from container
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic Programmatic Checks (Score: 20 max)
    score = 0
    feedback_parts = []
    
    # Criterion: App Running
    if task_result.get("app_running", False):
        score += 5
        feedback_parts.append("GCompris remained open.")
    else:
        feedback_parts.append("GCompris was closed prematurely.")

    # Criterion: Evidence Screenshot
    evidence_valid = False
    if task_result.get("evidence_exists", False):
        if task_result.get("file_created_during_task", False):
            if task_result.get("file_size_bytes", 0) > 10000: # >10KB
                score += 15
                evidence_valid = True
                feedback_parts.append("Evidence screenshot saved correctly.")
            else:
                feedback_parts.append("Evidence screenshot file is too small (likely empty).")
        else:
            feedback_parts.append("Evidence screenshot timestamp is invalid (pre-dates task).")
    else:
        feedback_parts.append("Evidence screenshot missing.")

    # 3. VLM Trajectory Verification (Score: 80 max)
    # We sample frames from the whole session to see the workflow
    frames = sample_trajectory_frames(traj, n=8)
    
    # Add the agent's specific evidence screenshot if it exists and is valid
    # Note: We can't easily pull the image content here without `copy_from_env` for the image file itself.
    # We will rely on the trajectory frames for the primary visual check.
    
    vlm_prompt = """
    You are verifying an agent performing a task in the educational software GCompris.
    
    Task: Navigate to the 'Double Entry Table' activity (a logic puzzle grid) and complete at least 2 levels.
    
    Analyze the sequence of screenshots. Look for:
    1. **Navigation**: Did the user find the activity? (Look for a grid icon or a screen with a large 2D table/matrix).
    2. **Gameplay**: Do you see items being dragged into a grid? The grid has row and column headers (e.g., color on one axis, shape on the other).
    3. **Success**: Do you see a 'Great', 'Flower', or 'Star' animation indicating a level was completed?
    4. **Progression**: Do you see the grid reset or change, indicating a second level was started or completed?
    
    Return a JSON object with:
    {
        "activity_found": true/false,
        "gameplay_observed": true/false,
        "level_1_complete": true/false,
        "level_2_started_or_complete": true/false,
        "confidence": "high/medium/low",
        "explanation": "Brief summary of what you saw"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        logger.info(f"VLM Analysis: {parsed}")
        
        if parsed.get("activity_found"):
            vlm_score += 20
            feedback_parts.append("VLM confirmed activity was found.")
            
        if parsed.get("gameplay_observed"):
            vlm_score += 20
            feedback_parts.append("VLM confirmed items were placed in the grid.")
            
        if parsed.get("level_1_complete"):
            vlm_score += 20
            feedback_parts.append("VLM confirmed Level 1 completion.")
            
        if parsed.get("level_2_started_or_complete"):
            vlm_score += 20
            feedback_parts.append("VLM confirmed progression to Level 2.")
            
        feedback_parts.append(f"VLM observation: {parsed.get('explanation', 'No details')}")
    else:
        feedback_parts.append("VLM verification failed to process images.")

    score += vlm_score

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }