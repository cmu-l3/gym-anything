#!/usr/bin/env python3
"""
Verifier for resize_master_bedroom task in DreamPlan Home Design.

Verification Strategy:
1. Anti-Gaming/Activity Check:
   - Verify DreamPlan was running at the end.
   - Verify a project file was saved/modified after task start.
   
2. VLM Trajectory Verification (Primary):
   - Use VLM to analyze trajectory frames.
   - Confirm agent navigated to floor plan view.
   - Confirm agent selected the specific bedroom wall.
   - Confirm agent dragged/moved the wall.
   - Confirm the final room appears wider than initial state.
"""

import json
import os
import logging
import tempfile
import sys
from typing import Dict, Any

# Adjust path to import vlm_utils from gym_anything
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../")))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resize_master_bedroom(traj, env_info, task_info):
    """
    Verifies that the agent resized the master bedroom by moving a wall.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Evidence
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: App Running (10 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("DreamPlan was open.")
    else:
        feedback_parts.append("DreamPlan was NOT open at end of task.")

    # Criterion 2: Project Saved (20 pts)
    if result.get('project_saved', False):
        score += 20
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file NOT saved (or no changes detected).")

    # Criterion 3: VLM Verification of Workflow (70 pts)
    # We need to see the wall moving
    frames = sample_trajectory_frames(traj, n=8)
    final_screenshot = get_final_screenshot(traj)
    
    if not frames:
        feedback_parts.append("No trajectory frames available for visual verification.")
    else:
        # Prompt for Process Verification
        process_prompt = """
        You are verifying a user performing a home design task in 'DreamPlan'.
        The user goal is: "Resize the master bedroom by moving a wall outward to make it wider."
        
        Look at the sequence of images and answer:
        1. Is the 'Blueprint' or '2D Floor Plan' view visible in most frames?
        2. Does the user select an interior wall (highlighted usually in blue or red when clicked)?
        3. Is there evidence of the wall being dragged or moved?
        4. Does the bedroom size change between the start and end of the sequence?
        
        Return JSON:
        {
            "floor_plan_view_visible": boolean,
            "wall_selected": boolean,
            "wall_moved": boolean,
            "room_size_changed": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_result = query_vlm(prompt=process_prompt, images=frames)
        
        if vlm_result.get('success'):
            analysis = vlm_result.get('parsed', {})
            
            if analysis.get('floor_plan_view_visible', False):
                score += 10
                feedback_parts.append("Floor plan view used.")
            
            if analysis.get('wall_selected', False):
                score += 15
                feedback_parts.append("Wall selection detected.")
                
            if analysis.get('wall_moved', False):
                score += 25
                feedback_parts.append("Wall movement action detected.")
            
            if analysis.get('room_size_changed', False):
                score += 20
                feedback_parts.append("Room size change visually confirmed.")
        else:
            feedback_parts.append("Visual verification failed (VLM error).")
            # If programmatic save passed, give minimal partial credit for "blind" success?
            # No, strictly require visual evidence for spatial tasks to prevent gaming.

    # Final scoring logic
    passed = score >= 60 and result.get('project_saved', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }