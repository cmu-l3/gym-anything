#!/usr/bin/env python3
"""
Verifier for create_backyard_fire_pit task.

Verification Strategy:
1. Anti-Gaming/File Checks (40 points):
   - Valid project file created/saved during task session.
   - Screenshot evidence saved by the agent.
   
2. VLM Visual Analysis (60 points):
   - Analyzes the agent's saved screenshot (or trajectory frames).
   - Confirms presence of Fire Pit.
   - Confirms presence of Chairs (at least 2).
   - Confirms Backyard context (greenery/outdoors).
   - Confirms Arrangement (grouping).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_backyard_fire_pit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # ==========================
    # CRITERION 1: File Checks
    # ==========================
    
    # Project File (20 pts)
    if result_data.get('project_exists') and result_data.get('project_created_during_task'):
        score += 20
        feedback_parts.append("Project file saved correctly.")
    elif result_data.get('project_exists'):
        score += 5
        feedback_parts.append("Project file exists but timestamp matches pre-task (did not save changes?).")
    else:
        feedback_parts.append("Project file not found.")

    # Screenshot File Existence (10 pts)
    # The agent is tasked to take a screenshot. If they did, it's a strong signal.
    # If not, we might fall back to trajectory, but the instructions required it.
    screenshot_path = result_data.get('screenshot_path')
    has_agent_screenshot = result_data.get('screenshot_exists') and result_data.get('screenshot_created_during_task')
    
    if has_agent_screenshot:
        score += 10
        feedback_parts.append("Agent saved the required screenshot.")
    else:
        feedback_parts.append("Agent did not save the required screenshot.")

    # App Running (10 pts)
    if result_data.get('app_was_running'):
        score += 10
    else:
        feedback_parts.append("DreamPlan was closed prematurely.")

    # ==========================
    # CRITERION 2: VLM Analysis
    # ==========================
    
    # We prioritize the screenshot the agent was asked to take (it likely has the best view).
    # If missing, we fall back to the final frame of the trajectory.
    image_to_analyze = None
    
    if has_agent_screenshot:
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(screenshot_path, temp_img.name)
            image_to_analyze = temp_img.name
        except Exception as e:
            logger.warning(f"Could not copy agent screenshot: {e}")
    
    if not image_to_analyze:
        image_to_analyze = get_final_screenshot(traj)

    if not image_to_analyze:
         return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No visual evidence available."
        }

    # VLM Prompt
    prompt = """
    You are evaluating a screenshot from a home design software (DreamPlan).
    The user was tasked to create a 'Backyard Fire Pit Area'.
    
    Please verify the following elements:
    1. Is there a FIRE PIT (or campfire/fire bowl) visible?
    2. Are there OUTDOOR CHAIRS (or benches) visible? How many?
    3. Are the chairs arranged around or near the fire pit (grouping)?
    4. Is the setting outdoors (e.g., green grass, terrain, patio, exterior walls)?
    
    Respond in JSON format:
    {
        "fire_pit_visible": true/false,
        "chairs_visible": true/false,
        "chair_count": <int>,
        "is_grouped": true/false,
        "is_outdoors": true/false,
        "description": "brief description of what you see"
    }
    """
    
    vlm_result = query_vlm(prompt=prompt, image=image_to_analyze)
    
    # Cleanup temp image if we made one
    if has_agent_screenshot and image_to_analyze and os.path.exists(image_to_analyze):
        os.unlink(image_to_analyze)

    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        # Fire Pit (20 pts)
        if parsed.get('fire_pit_visible'):
            score += 20
            feedback_parts.append("VLM confirmed fire pit.")
        else:
            feedback_parts.append("VLM did not detect a fire pit.")
            
        # Chairs (20 pts)
        chair_count = parsed.get('chair_count', 0)
        if parsed.get('chairs_visible') and chair_count >= 2:
            score += 20
            feedback_parts.append(f"VLM confirmed {chair_count} chairs.")
        elif parsed.get('chairs_visible'):
            score += 10
            feedback_parts.append(f"VLM found only {chair_count} chair(s) (needed 2).")
        else:
            feedback_parts.append("VLM did not detect chairs.")
            
        # Context (20 pts split)
        if parsed.get('is_outdoors'):
            score += 10
            feedback_parts.append("Location appears to be outdoors.")
        
        if parsed.get('is_grouped'):
            score += 10
            feedback_parts.append("Arrangement looks cohesive.")
            
    else:
        feedback_parts.append("VLM analysis failed.")

    # Calculate final pass/fail
    # Must have fire pit, chairs, and saved file to pass
    passed = (score >= 80) and result_data.get('project_created_during_task')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }