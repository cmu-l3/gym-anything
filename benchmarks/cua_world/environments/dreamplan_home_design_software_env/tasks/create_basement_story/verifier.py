#!/usr/bin/env python3
"""
Verifier for create_basement_story task.

Verifies:
1. Anti-gaming: Project file was actually modified during task.
2. Anti-gaming: Application is running.
3. VLM Trajectory: Verifies the "Stories" dialog was accessed.
4. VLM Final State: Verifies visual evidence of basement level (negative elevation/grid).
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Helper for VLM
def _query_vlm(query_vlm_func, prompt, images):
    if not query_vlm_func or not images:
        return None
    try:
        return query_vlm_func(prompt=prompt, images=images)
    except Exception as e:
        logger.error(f"VLM query failed: {e}")
        return None

def verify_create_basement_story(traj, env_info, task_info):
    """
    Verify the agent created a basement story and added walls.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Basic Metrics
    project_modified = result.get("project_file_modified", False)
    app_running = result.get("app_running", False)
    
    score = 0
    feedback_parts = []

    # Scoring - Basic State (30 pts)
    if app_running:
        score += 10
        feedback_parts.append("Application active")
    
    if project_modified:
        score += 20
        feedback_parts.append("Project file modified")
    else:
        feedback_parts.append("No project changes detected")

    # 4. VLM Verification (70 pts)
    # We need to sample frames to see the workflow
    # Logic: 
    # - Did we see the "Story" or "Level" dialog? (Workflow)
    # - Does the final view show a basement/foundation? (Result)

    if not traj:
        return {"passed": False, "score": score, "feedback": "No trajectory data available"}

    # Sample frames: Start, Middle (Workflow), End
    # Assuming traj is a list of steps, each has an 'observation'
    # This matches gym_anything structure
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        feedback_parts.append("No visual evidence available")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # VLM Prompt
    prompt = """
    You are verifying an architectural design task in NCH DreamPlan software.
    The task is: "Create a Basement Story".
    
    Review the sequence of screenshots. Look for:
    1. The "Edit Stories" or "Manage Stories" dialog box appearing.
    2. A story named "Basement" or a level with negative elevation (e.g., -8ft, -2.5m) being created.
    3. The view switching to a "below ground" mode (often indicated by a dark grid background or different shading).
    4. Walls being drawn on this new lower level (foundation walls).
    
    Answer the following in JSON:
    {
        "story_dialog_seen": boolean,
        "basement_created": boolean,
        "foundation_walls_visible": boolean,
        "final_view_is_basement": boolean,
        "confidence": "low|medium|high"
    }
    """

    vlm_resp = _query_vlm(query_vlm, prompt, frames)
    
    if vlm_resp and vlm_resp.get("success"):
        parsed = vlm_resp.get("parsed", {})
        
        # Criterion: Workflow (Dialog seen)
        if parsed.get("story_dialog_seen", False):
            score += 20
            feedback_parts.append("Story dialog accessed")
            
        # Criterion: Creation (Basement created)
        if parsed.get("basement_created", False):
            score += 25
            feedback_parts.append("Basement level created")
            
        # Criterion: Construction (Walls visible)
        if parsed.get("foundation_walls_visible", False) or parsed.get("final_view_is_basement", False):
            score += 25
            feedback_parts.append("Foundation walls visible")
            
    else:
        feedback_parts.append("Visual verification failed")

    # Pass Threshold
    # Needs 75 points.
    # Min path: App Running (10) + Project Modified (20) + Dialog Seen (20) + Basement Created (25) = 75
    # Full path: 100
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }