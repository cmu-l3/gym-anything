#!/usr/bin/env python3
"""
Verifier for configure_admin_password task.

Strategy:
1. Programmatic: Check if any configuration files were modified (evidence of saving settings).
2. VLM: Check trajectory frames to verify the agent found the security settings and entered the password.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_admin_password(traj, env_info, task_info):
    """
    Verify password configuration.
    
    Scoring:
    - 40 pts: Configuration/Database file modified (persistence check)
    - 60 pts: VLM verifies workflow (settings -> security -> password entry -> save)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get programmatic result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Persistence (File Modification) (40 pts) ---
    modified_files = result.get('modified_files', [])
    app_running = result.get('app_running', False)
    
    if not app_running:
        feedback_parts.append("Application crashed or was closed")
    
    if len(modified_files) > 0:
        score += 40
        feedback_parts.append(f"Settings saved to disk ({len(modified_files)} files modified)")
        logger.info(f"Modified files detected: {modified_files}")
    else:
        feedback_parts.append("No configuration files were modified (did you click Save?)")

    # --- Criterion 2: VLM Workflow Verification (60 pts) ---
    # We sample frames to catch the agent in the "Options" or "Security" menu
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying an agent configuring a password in "Lobby Track".
    Look at the sequence of screenshots.
    
    I need to confirm three things:
    1. Did the agent open a 'Settings', 'Options', 'Administration', or 'Preferences' dialog?
    2. Did the agent navigate to a 'Security', 'User Account', or 'Password' section?
    3. Did the agent type a password into a field (you might see masked characters like '****' or text in a field labeled Password)?
    
    Return JSON:
    {
      "settings_opened": boolean,
      "security_section_found": boolean,
      "password_entered": boolean,
      "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    vlm_score = 0
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('settings_opened'):
            vlm_score += 20
            feedback_parts.append("Found Settings menu")
        if parsed.get('security_section_found'):
            vlm_score += 20
            feedback_parts.append("Found Security section")
        if parsed.get('password_entered'):
            vlm_score += 20
            feedback_parts.append("Entered password")
    else:
        feedback_parts.append("VLM verification failed")

    score += vlm_score

    # Final logic
    passed = (score >= 70) # Needs file modification + at least partial VLM evidence
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }