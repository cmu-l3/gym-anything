#!/usr/bin/env python3
"""
Verifier for assign_primary_care_provider task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_primary_care_provider(traj, env_info, task_info):
    """
    Verifies that the agent assigned the correct Primary Care Provider.
    
    Criteria:
    1. (60 pts) Database Check: `patient_data.providerID` matches the Administrator's ID.
    2. (20 pts) State Change: The provider ID must have changed from the initial state (anti-gaming).
    3. (20 pts) VLM Verification: Trajectory confirms navigation to Demographics > Choices.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

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

    # 2. Evaluate Database State
    score = 0
    feedback_lines = []
    
    is_assigned = result.get("is_assigned", False)
    state_changed = result.get("state_changed", False)
    current_provider = result.get("current_provider_id", "Unknown")
    target_admin_id = result.get("admin_id", "Unknown")

    if is_assigned:
        score += 60
        feedback_lines.append("SUCCESS: Administrator is assigned as Provider in database.")
    else:
        feedback_lines.append(f"FAILURE: Database shows providerID {current_provider}, expected {target_admin_id}.")

    if state_changed:
        score += 20
        feedback_lines.append("Anti-gaming Pass: Database state correctly modified during task.")
    else:
        if is_assigned:
            feedback_lines.append("WARNING: Provider was already correct at start? (Anti-gaming check failed)")
        else:
            feedback_lines.append("No changes made to patient record.")

    # 3. VLM Trajectory Verification
    # We want to see that the agent actually navigated the UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent's actions in an Electronic Health Record (EHR) system.
    The goal was to assign a provider to a patient.
    
    Look for these key steps in the screenshots:
    1. A patient's chart is open.
    2. The 'Demographics' tab or section is active.
    3. The 'Choices' (or 'Stats'/'Misc') tab is visible, which contains the 'Provider' dropdown.
    4. A dropdown menu for 'Provider' is being interacted with.
    
    Return JSON:
    {
        "demographics_accessed": boolean,
        "choices_tab_seen": boolean,
        "provider_field_interaction": boolean,
        "reasoning": "string"
    }
    """
    
    try:
        # We pass the frames to the VLM
        vlm_response = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        vlm_data = vlm_response.get("parsed", {})
        
        vlm_score = 0
        if vlm_data.get("demographics_accessed"):
            vlm_score += 5
        if vlm_data.get("choices_tab_seen"):
            vlm_score += 5
        if vlm_data.get("provider_field_interaction"):
            vlm_score += 10
            
        score += vlm_score
        feedback_lines.append(f"VLM Verification: {vlm_data.get('reasoning', 'Analyzed trajectory')}")
        
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_lines.append("VLM Verification skipped due to error (awarding partial credit).")
        score += 10 # Grace points if VLM fails technically

    # 4. Final Result
    passed = (is_assigned and state_changed)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_lines)
    }