#!/usr/bin/env python3
"""
Verifier for replace_window_with_bay_window task in DreamPlan Home Design.

Verification Strategy:
1. File Verification (Secondary):
   - Check if 'RenovatedBayWindow.dpp' exists.
   - Verify it was modified during the task session.
   - Verify the file size suggests actual content (not empty).

2. VLM Verification (Primary):
   - Analyze trajectory frames to confirm the workflow:
     a) Selection/Deletion of existing window.
     b) Selection of "Bay Window" from the library.
     c) Placement of the new window.
   - Analyze final state to confirm visual outcome:
     a) Living room exterior wall shows a protruding bay window structure.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_replace_window_with_bay_window(traj, env_info, task_info):
    """
    Verify the agent replaced a standard window with a bay window.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Retrieve & Parse Task Result JSON (File System Checks)
    # ================================================================
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows envs, paths often map to /workspace inside the bridge/mount
        # But copy_from_env typically handles the mapping from the guest path
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        # Continue with defaults, VLM might still save the day
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    file_exists = task_result.get('file_exists', False)
    file_fresh = task_result.get('file_created_during_task', False)
    file_size = task_result.get('file_size_bytes', 0)
    app_running = task_result.get('app_running', False)

    # ================================================================
    # 2. VLM Verification (Trajectory & Final State)
    # ================================================================
    
    # Prompt for analyzing the workflow (Trajectory)
    trajectory_prompt = """
    You are analyzing the workflow of an agent using architectural design software (DreamPlan).
    The goal is to replace a standard window with a Bay Window.
    
    Review the sequence of images and determine if:
    1. The agent navigated to the 'Windows' or 'Doors & Windows' tool category.
    2. The agent deleted or removed an existing window (look for a hole in the wall or window disappearing).
    3. The agent selected a 'Bay Window' (a window with 3 angled panels projecting outward) from the catalog.
    4. The agent placed the new window into the wall.
    
    Return JSON:
    {
        "tools_accessed": boolean,
        "deletion_observed": boolean,
        "bay_window_selected": boolean,
        "placement_observed": boolean
    }
    """
    
    # Prompt for analyzing the final result (Final Screenshot)
    final_prompt = """
    Analyze this screenshot of the home design software.
    Focus on the windows visible in the 3D view or Floor Plan view.
    
    Is there a "Bay Window" installed? 
    A Bay Window is distinct because it protrudes/projects outward from the wall, usually with angled side panels.
    It should NOT be a flat standard window.
    
    Return JSON:
    {
        "bay_window_visible": boolean,
        "is_protruding": boolean,
        "confidence": number (0-10)
    }
    """

    # Execute VLM Queries
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    # Trajectory Analysis
    traj_response = query_vlm(images=frames, prompt=trajectory_prompt)
    traj_data = traj_response.get('parsed', {}) if traj_response.get('success') else {}
    
    # Final State Analysis
    final_response = query_vlm(image=final_frame, prompt=final_prompt)
    final_data = final_response.get('parsed', {}) if final_response.get('success') else {}

    # ================================================================
    # 3. Scoring Logic
    # ================================================================
    score = 0
    feedback_log = []

    # Criterion A: File System (25 points)
    if file_exists:
        score += 10
        feedback_log.append("Project file saved.")
        if file_fresh:
            score += 10
            feedback_log.append("Project saved during session.")
        else:
            feedback_log.append("Warning: Project file timestamp predates task.")
        
        if file_size > 1000: # Arbitrary small threshold for non-empty file
            score += 5
    else:
        feedback_log.append("Project file not found.")

    # Criterion B: Workflow (35 points)
    if traj_data.get('tools_accessed'):
        score += 5
    if traj_data.get('deletion_observed'):
        score += 10
        feedback_log.append("Old window removal observed.")
    if traj_data.get('bay_window_selected'):
        score += 10
        feedback_log.append("Bay window selection observed.")
    if traj_data.get('placement_observed'):
        score += 10
        feedback_log.append("Window placement observed.")

    # Criterion C: Final Visual Result (40 points)
    bay_visible = final_data.get('bay_window_visible', False)
    protruding = final_data.get('is_protruding', False)
    
    if bay_visible:
        score += 30
        feedback_log.append("Bay window visually confirmed.")
        if protruding:
            score += 10
            feedback_log.append("Window projects correctly.")
    else:
        feedback_log.append("Bay window NOT clearly visible in final state.")

    # Pass/Fail Determination
    # Must have saved file AND visual confirmation OR strong workflow evidence
    visual_success = bay_visible and score >= 60
    workflow_success = (traj_data.get('bay_window_selected') and traj_data.get('placement_observed')) and score >= 70
    
    passed = visual_success or workflow_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }