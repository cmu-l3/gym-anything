#!/usr/bin/env python3
"""
Verifier for configure_checkin_fields task.

Verification Logic:
1. Primary: VLM analysis of trajectory screenshots to confirm:
   - Navigation to settings/configuration
   - Visibility of field configuration panel
   - "Company", "Phone", "Purpose of Visit" checked as Required
2. Secondary: Configuration file timestamp updates (evidence of save)
3. Tertiary: Application stability (running at end)
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying a task in the Jolly Lobby Track visitor management software.
The user was asked to configure specific fields as REQUIRED (mandatory) for visitor check-in.

Examine the provided screenshots (sequence of actions).
Look specifically for a 'Settings', 'Options', or 'Field Configuration' screen.

I need you to answer these questions based on the visual evidence:
1. Did the user navigate to a settings or configuration menu?
2. Is the "Company" (or Organization) field visible and marked as REQUIRED?
3. Is the "Phone" (or Telephone) field visible and marked as REQUIRED?
4. Is the "Purpose of Visit" (or Reason) field visible and marked as REQUIRED?
5. Is there evidence that the settings were SAVED (e.g., clicking OK, Save, Apply)?

Respond in JSON format:
{
    "navigated_to_settings": true/false,
    "company_required": true/false,
    "phone_required": true/false,
    "purpose_required": true/false,
    "settings_saved": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see in the screenshots"
}
"""

def verify_configure_checkin_fields(traj, env_info, task_info):
    """
    Verify the field configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic programmatic results (file timestamps, app state)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check programmatic signals
    app_running = result.get("app_running", False)
    config_modified = result.get("config_files_modified", False)

    if app_running:
        score += 10
        feedback_parts.append("App still running (+10)")
    else:
        feedback_parts.append("App crashed or closed (0)")

    if config_modified:
        score += 10
        feedback_parts.append("Config files modified (Save detected) (+10)")
    else:
        feedback_parts.append("No config file changes detected")

    # 2. VLM Verification (Crucial for UI state)
    # Use trajectory frames to capture the configuration screen which might not be the final screen
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    # Combine frames, ensuring final is included
    verification_images = frames
    if final_frame:
        verification_images.append(final_frame)

    if not verification_images:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No screenshots available for verification"
        }

    try:
        vlm_response = query_vlm(
            images=verification_images,
            prompt=VLM_PROMPT
        )
        
        vlm_data = vlm_response.get("parsed", {})
        if not vlm_data:
            # Fallback if parsing failed
            logger.error(f"VLM parsing failed: {vlm_response}")
            vlm_data = {}

        # Scoring based on VLM
        if vlm_data.get("navigated_to_settings", False):
            score += 15
            feedback_parts.append("Navigated to settings (+15)")
        
        # Check specific fields
        fields_score = 0
        if vlm_data.get("company_required", False):
            fields_score += 20
            feedback_parts.append("Company set to Required (+20)")
        
        if vlm_data.get("phone_required", False):
            fields_score += 20
            feedback_parts.append("Phone set to Required (+20)")
            
        if vlm_data.get("purpose_required", False):
            fields_score += 20
            feedback_parts.append("Purpose set to Required (+20)")
            
        score += fields_score

        # Check save action visually if file timestamp didn't catch it
        if vlm_data.get("settings_saved", False) and not config_modified:
            score += 5
            feedback_parts.append("Visual evidence of saving (+5)")

        feedback_parts.append(f"VLM Reasoning: {vlm_data.get('reasoning', 'None')}")

    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM verification failed: {str(e)}")

    # Final Pass/Fail logic
    # Must have app running + navigated to settings + at least 2 fields correct
    passed = (app_running and 
              vlm_data.get("navigated_to_settings", False) and 
              fields_score >= 40)

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }