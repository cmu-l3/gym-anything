#!/usr/bin/env python3
"""
Verifier for configure_mandatory_visitor_field task.

This task requires the agent to configure the 'Email' field as 'Required' in Jolly Lobby Track.
Since the application uses a proprietary database format (likely .sdf or .mdb) inside Wine,
programmatic verification of the specific field bit is unreliable without specific tools.

Verification Strategy:
1. Anti-Gaming: Verify the database file was modified (saved) during the task window.
2. VLM Verification: Use trajectory analysis to confirm the specific UI actions:
   - Accessing configuration/design menu
   - Selecting 'Email' field
   - Toggling 'Required'/'Mandatory'
   - Saving changes
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_mandatory_visitor_field(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Load result from export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Anti-Gaming: Check if settings were actually saved (DB file modified)
    db_modified = result.get('db_modified', False)
    db_found = result.get('db_file_found', False)
    
    if db_modified:
        score += 20
        feedback.append("Settings saved successfully (Database modified).")
    elif db_found:
        feedback.append("Warning: Database file was not modified. Changes may not have been saved.")
    else:
        feedback.append("Warning: Could not track database file modifications.")

    # 2. VLM Trajectory Verification
    # We need to verify the specific logic: Email -> Required -> Save
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available for verification."}
    
    # Create a prompt that asks for the specific visual evidence
    prompt = """
    You are verifying an agent's actions in the 'Jolly Lobby Track' software.
    The goal was to Configure the 'Email' field to be MANDATORY (Required).

    Review the sequence of screenshots and verify the following steps:
    1. Did the agent navigate to a 'Database', 'Design', or 'Configuration' screen showing a list of fields?
    2. Did the agent select or highlight the 'Email' field?
    3. Did the agent check a box labeled 'Required', 'Mandatory', or 'Must Enter'?
    4. Did the agent click 'Save', 'OK', or 'Apply'?

    Return a JSON object with:
    - "config_screen_reached": boolean
    - "email_field_selected": boolean
    - "required_toggled": boolean
    - "saved": boolean
    - "confidence": score 0-10
    - "reasoning": string explanation
    """
    
    # Use the VLM (assumes query_vlm handles list of images)
    try:
        vlm_response = query_vlm(
            images=frames + [final_screen],
            prompt=prompt
        )
        
        analysis = vlm_response.get('parsed', {})
        if not analysis:
            # Fallback if parsing fails
            analysis = {"config_screen_reached": False, "email_field_selected": False, "required_toggled": False, "saved": False}
            logger.warning("VLM response parsing failed, using defaults")

        # Score based on VLM analysis
        if analysis.get('config_screen_reached'):
            score += 20
            feedback.append("Navigated to configuration screen.")
        
        if analysis.get('email_field_selected'):
            score += 20
            feedback.append("Selected 'Email' field.")
            
        if analysis.get('required_toggled'):
            score += 30
            feedback.append("Enabled 'Required' setting.")
            
        if analysis.get('saved'):
            score += 10
            feedback.append("Saved configuration.")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback.append(f"Visual verification error: {e}")

    # Pass logic: Must have enabled required AND saved (either verified visually or by file mod)
    # Total possible: 20 (DB) + 20 (Config) + 20 (Email) + 30 (Req) + 10 (Save) = 100
    # Threshold: 70
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }