#!/usr/bin/env python3
"""
Verifier for construct_freestanding_carport task.

Verification Strategy:
1. File Verification (30 pts): Checks if 'Carport_Design.dplan' was saved and modified during task.
2. VLM Trajectory Analysis (70 pts):
   - Confirms usage of Post/Column tools (not just walls).
   - Confirms usage of Manual Roof tools.
   - Verifies final structure is open-sided (carport) vs enclosed (garage).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_construct_freestanding_carport(traj, env_info, task_info):
    """
    Verify the agent constructed a freestanding carport using posts and a roof.
    """
    # 1. Setup and File Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_result_path = "C:\\workspace\\tasks\\construct_freestanding_carport\\task_result.json"
    
    score = 0
    feedback_parts = []
    
    # Load result from container
    file_check_passed = False
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env(remote_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_file.name)
        
        # Scoring: File Existence (15 pts)
        if result_data.get('output_exists'):
            score += 15
            feedback_parts.append("Project file saved.")
            
            # Scoring: Anti-gaming Timestamp (15 pts)
            if result_data.get('file_created_during_task'):
                score += 15
                file_check_passed = True
                feedback_parts.append("File verified as new/modified.")
            else:
                feedback_parts.append("Warning: File timestamp indicates no changes made.")
        else:
            feedback_parts.append("Project file 'Carport_Design' not found.")
            
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        feedback_parts.append(f"Error reading result file: {str(e)}")

    # 2. VLM Verification (Crucial for structural correctness)
    # We need to distinguish between a "Carport" (posts) and a "Garage" (walls)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame]
    
    prompt = """
    You are verifying an architectural design task in DreamPlan software.
    The user was asked to build a 'Freestanding Carport'.
    
    A valid Carport must have:
    1. VERTICAL POSTS or COLUMNS supporting the roof (not solid walls).
    2. OPEN SIDES (you can see through the structure).
    3. A ROOF covering the area.
    
    Look at the sequence of images and the final result.
    
    Q1: Did the user place vertical posts/columns? (Look for thin vertical elements, usage of 'Post' tool).
    Q2: Is the structure open-sided? (If it has solid walls enclosing it, it is a Garage, not a Carport).
    Q3: Is there a roof on top?
    Q4: Is it freestanding (separated from the main house)?
    
    Respond in JSON:
    {
        "posts_visible": boolean,
        "is_open_sided": boolean,
        "roof_visible": boolean,
        "is_freestanding": boolean,
        "tool_usage": "describe tools used (e.g. Wall, Post, Roof)",
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=all_images, prompt=prompt)
    
    vlm_passed = False
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Scoring Criteria
        
        # Posts Visible (20 pts)
        if parsed.get("posts_visible"):
            score += 20
            feedback_parts.append("Structural posts detected.")
        else:
            feedback_parts.append("No structural posts detected (required for carport).")
            
        # Open Sided (20 pts) - Penalize if it looks like a garage
        if parsed.get("is_open_sided"):
            score += 20
            feedback_parts.append("Structure is open-sided.")
        else:
            feedback_parts.append("Structure appears enclosed (looks like a garage, not a carport).")
            
        # Roof Visible (20 pts)
        if parsed.get("roof_visible"):
            score += 20
            feedback_parts.append("Roof detected.")
        else:
            feedback_parts.append("No roof detected.")
            
        # Bonus: Freestanding (10 pts)
        if parsed.get("is_freestanding"):
            score += 10
            feedback_parts.append("Structure is freestanding.")
            
        if parsed.get("posts_visible") and parsed.get("roof_visible") and parsed.get("is_open_sided"):
            vlm_passed = True
            
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # Final logic
    # Must have saved file AND passed visual inspection of posts+roof
    passed = file_check_passed and vlm_passed
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }