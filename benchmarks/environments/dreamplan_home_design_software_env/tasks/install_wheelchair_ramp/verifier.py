#!/usr/bin/env python3
"""
Verifier for install_wheelchair_ramp task.

VERIFICATION STRATEGY:
1. File Verification (20 pts):
   - Agent saved a screenshot as requested.
   - Project file was modified (saved) during task.

2. VLM Verification (80 pts):
   - Uses trajectory frames to verify the "Ramp" tool was selected.
   - Uses final screenshot/state to verify a ramp is visible, sloped, and connected.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_wheelchair_ramp(traj, env_info, task_info):
    """
    Verify wheelchair ramp installation using VLM and file artifacts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON Result from Container
    # Note: Path corresponds to $DocDir\task_result.json in export script
    remote_json_path = r"C:\Users\Docker\Documents\task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_json_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: File Artifacts (20 pts) ---
    # Check if agent took the requested screenshot
    if result.get('screenshot_exists') and result.get('screenshot_created_during_task'):
        score += 10
        feedback_parts.append("Screenshot file created successfully.")
    else:
        feedback_parts.append("Failed to save screenshot to requested path.")

    # Check if project was saved
    if result.get('project_modified'):
        score += 10
        feedback_parts.append("Project changes saved.")
    else:
        feedback_parts.append("Project file not modified (changes not saved).")

    # --- CRITERION 2: VLM Trajectory Analysis (30 pts) ---
    # Did they use the Ramp tool?
    frames = sample_trajectory_frames(traj, n=8)
    
    tool_prompt = """
    Analyze these screenshots of a home design software workflow.
    I am looking for evidence that the user selected the 'Ramp' tool.
    
    Look for:
    1. Navigation to 'Building' tab or 'Stairs' category.
    2. Selection of a button labeled 'Ramp' (distinct from Stairs/Ladders).
    3. A cursor placing a sloped object.
    
    Did the user interact with the Ramp tool?
    """
    
    tool_check = query_vlm(images=frames, prompt=tool_prompt)
    tool_success = tool_check.get('parsed', {}).get('answer', False) if isinstance(tool_check.get('parsed'), dict) else "yes" in str(tool_check).lower()
    
    # Simple boolean fallback if parsing fails
    if "yes" in str(tool_check).lower() or tool_success:
        score += 30
        feedback_parts.append("VLM confirmed usage of Ramp tool.")
    else:
        feedback_parts.append("VLM could not confirm Ramp tool selection from trajectory.")

    # --- CRITERION 3: VLM Final State Analysis (50 pts) ---
    # Check the final result for the ramp
    final_img = get_final_screenshot(traj)
    
    ramp_prompt = """
    Look at this screenshot of a 3D home design view.
    I need to verify if a wheelchair access ramp has been installed at the front entrance.
    
    Check for:
    1. OBJECT: Is there a ramp (smooth inclined plane) visible? (NOT steps/stairs)
    2. LOCATION: Is it attached to the front porch/entrance?
    3. SLOPE: Does it connect the ground level to the porch level?
    4. RAILINGS: Does the ramp have safety railings on the sides?
    
    Respond in JSON:
    {
        "ramp_visible": true/false,
        "is_not_stairs": true/false,
        "connected_to_porch": true/false,
        "railings_visible": true/false
    }
    """
    
    final_check = query_vlm(image=final_img, prompt=ramp_prompt)
    parsed_final = final_check.get('parsed', {})
    
    # Score breakdown for final state
    if parsed_final.get('ramp_visible'):
        score += 20
        feedback_parts.append("Ramp object visible.")
        
        if parsed_final.get('is_not_stairs'):
            score += 10
            feedback_parts.append("Object is correctly identified as a ramp (not stairs).")
        else:
            feedback_parts.append("Warning: Object looks like stairs, not a smooth ramp.")
            
        if parsed_final.get('connected_to_porch'):
            score += 10
            feedback_parts.append("Ramp is connected to porch.")
            
        if parsed_final.get('railings_visible'):
            score += 10
            feedback_parts.append("Railings are visible.")
    else:
        feedback_parts.append("No ramp visible in final screenshot.")

    # --- Final Scoring ---
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }