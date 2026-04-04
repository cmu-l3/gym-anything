#!/usr/bin/env python3
"""
Verifier for create_user_group_permissions task.

Verification Logic:
1. Primary: Check MySQL database for the 'PRMSALES' user group with specific fields.
2. Anti-Gaming: Ensure group count increased during task (created, not pre-existing).
3. Secondary: VLM verification of trajectory to ensure UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_group_permissions(traj, env_info, task_info):
    """
    Verify the Vicidial User Group creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Define scoring weights
    SCORING = {
        "group_exists": 15,
        "group_name": 15,
        "group_level": 15,
        "forced_timeclock": 12,
        "shift_enforcement": 13,
        "allowed_campaigns": 15,
        "anti_gaming": 10,
        "vlm_ui": 5
    }
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Load Result JSON
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_data = result.get("db_data", {})
    group_exists = result.get("group_exists", False)
    
    # ================================================================
    # 2. Database Verification
    # ================================================================
    
    # Criterion: Group exists (15 pts) - Mandatory for passing
    if group_exists and db_data.get("user_group") == "PRMSALES":
        score += SCORING["group_exists"]
        feedback_parts.append("User group 'PRMSALES' created.")
    else:
        feedback_parts.append("FAIL: User group 'PRMSALES' not found in database.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Criterion: Group Name (15 pts)
    expected_name = metadata.get("expected_name", "Premium Sales Division")
    actual_name = db_data.get("group_name", "")
    if actual_name == expected_name:
        score += SCORING["group_name"]
        feedback_parts.append(f"Name correct.")
    else:
        feedback_parts.append(f"Name mismatch (Expected: '{expected_name}', Got: '{actual_name}').")

    # Criterion: Group Level (15 pts)
    expected_level = str(metadata.get("expected_level", "7"))
    actual_level = str(db_data.get("group_level", ""))
    if actual_level == expected_level:
        score += SCORING["group_level"]
        feedback_parts.append("Level correct.")
    else:
        feedback_parts.append(f"Level mismatch (Expected: {expected_level}, Got: {actual_level}).")

    # Criterion: Forced Timeclock (12 pts)
    expected_timeclock = metadata.get("expected_timeclock", "Y")
    actual_timeclock = db_data.get("forced_timeclock_login", "")
    if actual_timeclock == expected_timeclock:
        score += SCORING["forced_timeclock"]
        feedback_parts.append("Timeclock setting correct.")
    else:
        feedback_parts.append(f"Timeclock mismatch (Expected: {expected_timeclock}, Got: {actual_timeclock}).")

    # Criterion: Shift Enforcement (13 pts)
    expected_shift = metadata.get("expected_shift", "START")
    actual_shift = db_data.get("shift_enforcement", "")
    if actual_shift == expected_shift:
        score += SCORING["shift_enforcement"]
        feedback_parts.append("Shift enforcement correct.")
    else:
        feedback_parts.append(f"Shift mismatch (Expected: {expected_shift}, Got: {actual_shift}).")

    # Criterion: Allowed Campaigns (15 pts)
    # The token usually stored is " -ALL-CAMPAIGNS- " or similar.
    # We check for substring presence of "ALL-CAMPAIGNS" or "ALL CAMPAIGNS"
    actual_campaigns = db_data.get("allowed_campaigns", "")
    if "ALL-CAMPAIGNS" in actual_campaigns or "ALL CAMPAIGNS" in actual_campaigns:
        score += SCORING["allowed_campaigns"]
        feedback_parts.append("Allowed campaigns correct.")
    else:
        # Partial credit if they added *something* but maybe not ALL
        if len(actual_campaigns) > 5:
            score += 5
            feedback_parts.append("Allowed campaigns partially set (ALL CAMPAIGNS missing).")
        else:
            feedback_parts.append("Allowed campaigns not set correctly.")

    # ================================================================
    # 3. Anti-Gaming Verification (10 pts)
    # ================================================================
    anti_gaming = result.get("anti_gaming", {})
    if anti_gaming.get("count_increased", False):
        score += SCORING["anti_gaming"]
        feedback_parts.append("New record created (anti-gaming pass).")
    else:
        # If group exists but count didn't increase, they might have edited an existing one
        # or we had a cleanup issue. We penalize but don't fail if the data is right.
        feedback_parts.append("Warning: Group count did not increase.")

    # ================================================================
    # 4. VLM Verification (5 pts)
    # ================================================================
    # We want to confirm they used the UI, not just SQL injection (though unlikely in this env)
    # Use trajectory frames
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying a user interacting with the Vicidial Administration Interface.
    
    Look for these specific visual indicators in the sequence of screenshots:
    1. The Vicidial Admin header (often blue/grey with 'ADMINISTRATION').
    2. A form with fields like 'Group ID', 'Group Name', 'Group Level'.
    3. The text 'User Groups' or 'Show User Groups'.
    
    Did the user access the User Groups section and interact with a form?
    Respond with JSON: {"interaction_confirmed": true/false, "reason": "..."}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("interaction_confirmed"):
            score += SCORING["vlm_ui"]
            feedback_parts.append("VLM confirmed UI interaction.")
        else:
            feedback_parts.append("VLM could not confirm UI interaction.")
    else:
        # Fallback: if VLM fails, check if final screenshot exists
        if os.path.exists(temp_file.name) and result.get("screenshot_path"): # Just check if we got a result
             # Give partial points for having a screenshot if VLM fails technically
             score += 2 
             feedback_parts.append("VLM skipped, screenshot present.")

    # ================================================================
    # Final Result
    # ================================================================
    passed = score >= 60 and group_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }