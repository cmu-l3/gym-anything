#!/usr/bin/env python3
"""
Verifier for add_backyard_gazebo task.

Verifies that the agent placed a Gazebo structure in the backyard area.

Strategy:
1. Anti-gaming: Check if project file was actually modified (via file timestamps).
2. VLM Trajectory: Verify workflow (Library navigation -> Selection -> Placement).
3. VLM Final State: Verify a gazebo-like structure exists in the backyard.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_backyard_gazebo(traj, env_info, task_info):
    """
    Verify gazebo placement using VLM and file system evidence.
    """
    # 1. Setup and copy result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    score = 0
    feedback_parts = []
    
    # Read result.json from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Criterion: Project Modification (Anti-Gaming) - 20 pts
    if result_data.get("project_modified", False):
        score += 20
        feedback_parts.append("Project file saved/modified successfully")
    else:
        feedback_parts.append("No changes saved to project file")

    # 3. VLM Verification
    frames = sample_trajectory_frames(traj, n=5)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No visual evidence available"}

    # VLM Query 1: Final State Content (40 pts)
    final_prompt = """
    Analyze this screenshot of the DreamPlan Home Design Software.
    I am looking for a specific outdoor structure in the backyard area.
    
    1. Is the view showing a 2D floor plan or 3D view of a house/property?
    2. Do you see a GAZEBO, pavilion, or similar freestanding roofed structure?
    3. Is this structure located in the BACKYARD (behind the main house)?
    4. Is the structure SEPARATE from the house (not a deck attached to the wall)?
    
    Respond in JSON:
    {
        "view_type": "2D/3D/Other",
        "gazebo_visible": true/false,
        "is_in_backyard": true/false,
        "is_freestanding": true/false,
        "description": "brief description of what you see"
    }
    """
    
    vlm_final = query_vlm(prompt=final_prompt, image=final_screenshot)
    
    if vlm_final.get("success"):
        parsed = vlm_final.get("parsed", {})
        if parsed.get("gazebo_visible"):
            score += 20
            feedback_parts.append("Gazebo structure visible")
            
            if parsed.get("is_in_backyard"):
                score += 10
                feedback_parts.append("Correctly placed in backyard")
            else:
                feedback_parts.append("Structure found but location might be wrong")
                
            if parsed.get("is_freestanding"):
                score += 10
                feedback_parts.append("Structure is freestanding")
        else:
            feedback_parts.append("No gazebo visible in final view")
    else:
        feedback_parts.append("Visual analysis failed")

    # VLM Query 2: Workflow Trajectory (40 pts)
    # Check if they actually accessed the library
    traj_prompt = """
    Analyze these frames from a home design session. 
    The user should be selecting a Gazebo from the object library and placing it.
    
    Look for:
    1. Opening a library/menu (like 'Exterior', 'Garden', 'Plants', or 'Structures').
    2. Selecting an item that looks like a GAZEBO.
    3. The act of placing it on the terrain.
    
    Respond in JSON:
    {
        "library_accessed": true/false,
        "gazebo_selected": true/false,
        "placement_action_observed": true/false
    }
    """
    
    vlm_traj = query_vlm(prompt=traj_prompt, images=frames)
    
    if vlm_traj.get("success"):
        parsed = vlm_traj.get("parsed", {})
        if parsed.get("library_accessed"):
            score += 10
        if parsed.get("gazebo_selected"):
            score += 20
            feedback_parts.append("Verified selection of Gazebo from library")
        if parsed.get("placement_action_observed"):
            score += 10
    
    # Final Score Calculation
    # Pass threshold: 60 points + Gazebo must be visible OR selected+placed
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }