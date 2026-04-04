#!/usr/bin/env python3
"""
Verifier for Create Operator Accounts task in Copper POS.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_operator_accounts(traj, env_info, task_info):
    """
    Verify that two specific operator accounts were created.
    
    Verification Logic:
    1. Programmatic: Check if names exist in Copper data files (retrieved via export script).
    2. Programmatic: Check if data files were modified during task window (anti-gaming).
    3. VLM: Check trajectory for navigation to Employee/Operator settings and form filling.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path in container is C:\workspace\task_result.json
        # The copy_from_env implementation handles the OS path conversion if set up correctly,
        # otherwise we assume the agent mount maps C:\workspace to /workspace inside the VM context logic
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Scoring
    score = 0
    feedback_parts = []
    
    # Check data modification (Anti-gaming)
    if result.get("data_modified_during_task", False):
        score += 10
        feedback_parts.append("Data files modified successfully.")
    else:
        feedback_parts.append("No data files were modified (did you save?).")

    # Check for specific names
    found_emily = result.get("found_emily", False)
    found_james = result.get("found_james", False)

    if found_emily:
        score += 25
        feedback_parts.append("Operator 'Emily Rodriguez' found in database.")
    else:
        feedback_parts.append("Operator 'Emily Rodriguez' NOT found.")

    if found_james:
        score += 25
        feedback_parts.append("Operator 'James Nakamura' found in database.")
    else:
        feedback_parts.append("Operator 'James Nakamura' NOT found.")

    # 3. VLM Verification
    # We check if the user actually navigated to the operator settings
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a Point of Sale system interaction.
    The user was tasked with adding new employees/operators.
    
    Look for:
    1. Navigation to an "Operators", "Employees", or "Salesperson" list/settings screen.
    2. A form being filled out with names like "Emily" or "James".
    3. A list showing multiple operators in the final state.
    
    Return JSON:
    {
        "settings_opened": boolean,
        "names_entered": boolean,
        "final_list_visible": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("settings_opened"):
            vlm_score += 10
            feedback_parts.append("VLM: Navigation to settings verified.")
        if parsed.get("names_entered"):
            vlm_score += 15
            feedback_parts.append("VLM: Name entry verified.")
        if parsed.get("final_list_visible"):
            vlm_score += 15
            feedback_parts.append("VLM: Updated operator list visible.")
    
    score += vlm_score

    # Final Pass Logic
    # Must have found both names in data AND have some visual confirmation or file modification
    key_programmatic_pass = found_emily and found_james
    passed = score >= 60 and key_programmatic_pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }