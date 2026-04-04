#!/usr/bin/env python3
"""
Verifier for configure_contractor_group task.

Strategy:
1. Programmatic: Check if "Contractors" string appears in application database/config.
2. Visual (VLM): Check if "Contractors" button is visible on the main menu.
3. Visual (VLM): Verify trajectory shows interaction with Settings/Groups.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_contractor_group(traj, env_info, task_info):
    """
    Verifies that the agent configured the 'Contractors' visitor group.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Programmatic Check (Database/Config) - 30 points
    # ------------------------------------------------------------------
    contractors_found = result.get("contractors_string_found", False)
    config_modified = result.get("config_files_modified", False)
    
    if contractors_found:
        score += 30
        feedback_parts.append("Database configuration updated with 'Contractors' group.")
    elif config_modified:
        score += 10
        feedback_parts.append("Configuration files were modified, but 'Contractors' string not found.")
    else:
        feedback_parts.append("No configuration changes detected in database.")

    # ------------------------------------------------------------------
    # 2. VLM Verification (Trajectory & Final State) - 70 points
    # ------------------------------------------------------------------
    # We use VLM to verify the actual UI state, which is the ultimate truth for this task.
    # The database string check is a good backup, but the button visibility is the goal.
    
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    # Prompt focuses on the MAIN GOAL: The button on the dashboard.
    prompt = """
    You are verifying a software configuration task in Jolly Lobby Track.
    
    The Goal: The user should have renamed the 'Members' group to 'Contractors' and enabled it on the Main Menu.
    
    Please analyze the images (trajectory and final screenshot):
    1. Look at the FINAL screenshot. Do you see a large button labeled "Contractors" on the main dashboard/menu?
       (It should look similar to the 'Visitors' button usually found there).
    2. Look at the TRAJECTORY frames. Did the user navigate to a Settings/Setup screen?
    3. Did the user edit a group named 'Members' or create a new group?
    
    Respond in JSON format:
    {
        "contractors_button_visible": boolean,
        "settings_accessed": boolean,
        "group_renamed_or_created": boolean,
        "explanation": "string"
    }
    """
    
    vlm_response = query_vlm(
        images=trajectory_frames + [final_screenshot],
        prompt=prompt
    )
    
    vlm_data = vlm_response.get("parsed", {})
    if not vlm_data:
        # Fallback if parsing fails
        logger.error(f"VLM parsing failed. Raw: {vlm_response}")
        return {"passed": False, "score": score, "feedback": "VLM verification failed to parse."}

    # Score VLM components
    if vlm_data.get("contractors_button_visible", False):
        score += 40
        feedback_parts.append("Visual verification: 'Contractors' button is visible on Main Menu.")
    else:
        feedback_parts.append("Visual verification: 'Contractors' button NOT found on Main Menu.")

    if vlm_data.get("settings_accessed", False):
        score += 15
        feedback_parts.append("Visual verification: Settings menu was accessed.")

    if vlm_data.get("group_renamed_or_created", False):
        score += 15
        feedback_parts.append("Visual verification: Group editing detected.")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    # Pass requires:
    # 1. 'Contractors' button visible (Highest importance)
    # OR
    # 2. Database string found AND some visual evidence of work
    
    passed = False
    if vlm_data.get("contractors_button_visible", False):
        passed = True
    elif contractors_found and (vlm_data.get("settings_accessed", False) or vlm_data.get("group_renamed_or_created", False)):
        # Partial credit pass: They did the backend work but maybe button isn't clearly visible in screenshot
        # But for full pass, we really want that button.
        # Let's set a score threshold.
        passed = score >= 70
    
    # Cap score at 100
    score = min(100, score)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "vlm_analysis": vlm_data,
            "db_check": {"contractors_found": contractors_found}
        }
    }