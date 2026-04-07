#!/usr/bin/env python3
"""
Verifier for create_new_user_profile task.
Checks if the OpenBCI GUI user profile was created and if the session is running.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_new_user_profile(traj, env_info, task_info):
    """
    Verify creation of 'Subject_Alpha' profile.
    
    Criteria:
    1. Profile artifacts exist on disk (Directory or JSON entry) (50 pts)
    2. Artifacts created DURING task (Anti-gaming) (20 pts)
    3. Application is still running (Session active) (30 pts)
    4. VLM verification of GUI state (Trajectory check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Profile Exists (50 pts)
    profile_found = result.get("profile_found", False)
    if profile_found:
        score += 50
        feedback_parts.append("Profile 'Subject_Alpha' found")
    else:
        feedback_parts.append("Profile 'Subject_Alpha' NOT found")

    # Criterion 2: Created During Task (20 pts)
    created_fresh = result.get("artifact_created_during_task", False)
    if created_fresh:
        score += 20
        feedback_parts.append("Profile created during task")
    elif profile_found:
        feedback_parts.append("Profile existed before task (old data used?)")

    # Criterion 3: App Running (30 pts)
    app_running = result.get("app_running", False)
    if app_running:
        score += 30
        feedback_parts.append("OpenBCI GUI is running")
    else:
        feedback_parts.append("OpenBCI GUI is NOT running")

    # VLM Verification (Bonus/Confirmation)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        I am analyzing an agent's interaction with OpenBCI GUI.
        Goal: Create a user profile named "Subject_Alpha" and start a session.
        
        Look at the image sequence. 
        1. Do you see the user typing "Subject_Alpha" or selecting "New User"?
        2. Does the final screen show a running graph/session?
        
        Answer with JSON: {"user_creation_visible": bool, "session_active": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('user_creation_visible'):
                feedback_parts.append("(VLM confirmed user creation step)")
            if parsed.get('session_active'):
                feedback_parts.append("(VLM confirmed active session)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final Pass Logic
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }