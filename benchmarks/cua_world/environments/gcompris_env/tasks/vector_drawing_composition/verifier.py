#!/usr/bin/env python3
"""
Verifier for vector_drawing_composition task.

Verification Strategy:
1. File Verification (30 points):
   - Check if ~/Documents/drawing_composition.png exists
   - Check if it was created during the task window
   - Check if it is a valid image file > 10KB

2. VLM Content Verification (70 points):
   - Use the saved output image (drawing_composition.png) AND trajectory frames.
   - Verify specific geometric elements:
     - House body (Rectangle/Square)
     - Roof (Triangle)
     - Sun (Circle)
   - Verify color usage (at least 2 colors)
   - Verify tool usage (trajectory shows GCompris Vector Drawing interface)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vector_drawing_composition(traj, env_info, task_info):
    """
    Verify the vector drawing task using file checks and VLM analysis.
    """
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 2. Retrieve Task Result JSON from container
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 3. File Verification (30 pts)
    output_exists = task_result.get("output_exists", False)
    file_created = task_result.get("file_created_during_task", False)
    file_size = task_result.get("output_size_bytes", 0)
    
    output_image_local_path = None

    if output_exists:
        if file_size > 10240: # > 10KB
            score += 15
            feedback_parts.append("Output file exists and has valid size.")
            
            # Download the actual image for VLM analysis
            try:
                temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                copy_from_env(task_result["output_path"], temp_img.name)
                output_image_local_path = temp_img.name
            except Exception as e:
                feedback_parts.append(f"Warning: Could not retrieve output image for VLM: {e}")
        else:
            feedback_parts.append("Output file is too small (likely empty/black).")
            
        if file_created:
            score += 15
            feedback_parts.append("File was created during the task.")
        else:
            feedback_parts.append("File timestamp indicates it was not created during this session.")
    else:
        feedback_parts.append("No output file found at ~/Documents/drawing_composition.png.")

    # 4. VLM Verification (70 pts)
    # We analyze the user's specific output file if it exists, otherwise we look at the final screenshot
    # We also check trajectory to ensure they used the correct tool
    
    images_to_analyze = []
    
    # Add trajectory frames (to verify tool usage)
    traj_frames = sample_trajectory_frames(traj, n=3)
    images_to_analyze.extend(traj_frames)
    
    # Add the final result image (primary evidence of drawing)
    if output_image_local_path:
        images_to_analyze.append(output_image_local_path)
    else:
        # Fallback to final system screenshot if they didn't save the file correctly but drew it
        final_ss = get_final_screenshot(traj)
        if final_ss:
            images_to_analyze.append(final_ss)

    if not images_to_analyze:
        return {"passed": False, "score": score, "feedback": "No visual evidence available (no file, no screenshots)."}

    prompt = """
    You are evaluating a GCompris educational task.
    The user was asked to use the 'Vector Drawing' tool to draw:
    1. A House (Square body + Triangular roof)
    2. A Sun (Circle)
    3. Using at least 2 different colors.

    Look at the provided images (trajectory and final output).
    
    Determine:
    - Did the user open the 'Vector Drawing' activity? (Look for drawing tools sidebar, vector nodes, grid)
    - Is there a House-like structure? (Rectangle + Triangle)
    - Is there a Sun-like structure? (Circle, usually yellow/orange, in the sky)
    - Are there multiple colors used?

    Return JSON:
    {
        "tool_opened": boolean,
        "house_visible": boolean,
        "sun_visible": boolean,
        "colors_used": boolean,
        "feedback": "string explaining what you see"
    }
    """
    
    try:
        vlm_response = query_vlm(
            prompt=prompt,
            images=images_to_analyze
        )
        
        if vlm_response.get("success"):
            analysis = vlm_response.get("parsed", {})
            logger.info(f"VLM Analysis: {analysis}")
            
            if analysis.get("tool_opened", False):
                score += 10
                feedback_parts.append("Correct Vector Drawing tool used.")
            else:
                feedback_parts.append("Could not verify Vector Drawing tool usage.")

            if analysis.get("house_visible", False):
                score += 25
                feedback_parts.append("House (body+roof) visible.")
            else:
                feedback_parts.append("House not clearly visible.")

            if analysis.get("sun_visible", False):
                score += 25
                feedback_parts.append("Sun visible.")
            else:
                feedback_parts.append("Sun not clearly visible.")

            if analysis.get("colors_used", False):
                score += 10
                feedback_parts.append("Multiple colors used.")
            else:
                feedback_parts.append("Drawing appears monochromatic or empty.")
                
            feedback_parts.append(f"VLM Feedback: {analysis.get('feedback', 'No details')}")
            
        else:
            feedback_parts.append("VLM analysis failed.")
            
    except Exception as e:
        logger.error(f"VLM Verification Error: {e}")
        feedback_parts.append("Error performing visual verification.")
    finally:
        if output_image_local_path and os.path.exists(output_image_local_path):
            os.unlink(output_image_local_path)

    # 5. Final Result Calculation
    passed = score >= 70  # Requires file + most drawing elements OR perfect drawing visible in screenshot
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }