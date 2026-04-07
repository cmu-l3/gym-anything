#!/usr/bin/env python3
"""
Verifier for add_custom_vehicle_field task.

Checks:
1. Agent created the requested verification screenshot (File check)
2. Visitor data (License Plate) persisted to database (File/Grep check)
3. VLM verifies the screenshot shows the correct field and data
4. VLM verifies the trajectory shows configuration steps
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_custom_vehicle_field(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    expected_plate = metadata.get('license_plate', '7XKP392')
    
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Programmatic Checks (40 points)
    # ------------------------------------------------------------------
    
    # Check 1: Screenshot file exists and was created during task (10 pts)
    if result.get('screenshot_exists') and result.get('screenshot_valid_timestamp'):
        score += 10
        feedback_parts.append("Screenshot created successfully.")
    elif result.get('screenshot_exists'):
        score += 5
        feedback_parts.append("Screenshot exists but timestamp is suspicious.")
    else:
        feedback_parts.append("Verification screenshot not found.")

    # Check 2: Database Persistence (30 pts)
    # This confirms the "Save" action actually committed data
    if result.get('database_license_plate_found'):
        score += 20
        feedback_parts.append(f"License plate '{expected_plate}' found in database.")
    else:
        feedback_parts.append(f"License plate '{expected_plate}' NOT found in database.")

    if result.get('database_visitor_found'):
        score += 10
        feedback_parts.append("Visitor name found in database.")

    # ------------------------------------------------------------------
    # 2. VLM Verification (60 points)
    # ------------------------------------------------------------------
    
    # Prepare VLM inputs
    # We check the specific user-generated screenshot if available, otherwise final state
    # But for trajectory analysis we need frames
    frames = sample_trajectory_frames(traj, n=8)
    final_screen = get_final_screenshot(traj)
    
    # Check 3: Configuration Workflow (20 pts)
    # Did they go to settings?
    workflow_prompt = """
    Analyze these screenshots of a user interacting with visitor management software.
    I am looking for evidence that the user accessed a 'Settings', 'Configuration', 'Design', or 'Options' menu.
    
    Do you see any frames showing:
    1. A settings dialog or menu?
    2. A 'Field' customization or 'Form' designer screen?
    3. The user adding or enabling a checkbox/field?
    
    Answer with YES or NO and a brief reason.
    """
    
    workflow_result = query_vlm(images=frames, prompt=workflow_prompt)
    workflow_passed = "yes" in workflow_result.get('response', '').lower()
    
    if workflow_passed:
        score += 20
        feedback_parts.append("VLM confirmed navigation to configuration settings.")
    else:
        feedback_parts.append("VLM did not detect configuration/settings menu access.")

    # Check 4: Final Output Verification (40 pts)
    # Does the form show the license plate field?
    
    # We prefer the user's saved screenshot if possible, but we don't have easy access to it 
    # via 'copy_from_env' as an image object here without extra steps. 
    # We rely on the final state screenshot from the framework which should show the result 
    # if the agent followed instructions to leave it open/visible.
    
    output_prompt = f"""
    Analyze this screenshot of the Jolly Lobby Track visitor software.
    
    I am looking for a visitor record for "Carlos Mendez".
    Specifically, look for a field named "Vehicle", "License Plate", "Car", or similar.
    
    1. Is the name "Carlos Mendez" visible?
    2. Is there a field for Vehicle/License Plate?
    3. Is the value "{expected_plate}" visible in that field?
    
    Answer JSON: {{ "visitor_visible": bool, "field_visible": bool, "value_match": bool }}
    """
    
    vlm_final = query_vlm(images=[final_screen], prompt=output_prompt)
    try:
        analysis = json.loads(vlm_final.get('response', '{}').replace("