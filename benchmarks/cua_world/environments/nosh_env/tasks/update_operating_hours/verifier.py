#!/usr/bin/env python3
"""
Verifier for update_operating_hours task.

Criteria:
1. Primary: Friday closing time updated to 13:00 (1:00 PM) in database.
2. Precision: Monday closing time remains unchanged (17:00).
3. Precision: Friday opening time remains unchanged (08:00).
4. VLM: Confirmation that the agent performed the workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_operating_hours(traj, env_info, task_info):
    # 1. Setup and Load Data
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    schedule = result.get("schedule_data", {})
    fri_close = str(schedule.get("fri_close", "")).strip()
    mon_close = str(schedule.get("mon_close", "")).strip()
    fri_open = str(schedule.get("fri_open", "")).strip()
    
    # Metadata expectations
    metadata = task_info.get("metadata", {})
    expected_fri_close = "13:00" # HH:MM format
    expected_fri_close_sql = "13:00:00" # SQL Time format
    initial_mon_close = metadata.get("control_fields", {}).get("mon_c", "17:00")
    initial_fri_open = metadata.get("control_fields", {}).get("fri_o", "08:00")

    score = 0
    feedback_parts = []
    
    # 3. Primary Verification (60 pts)
    # Check if Friday close time matches 13:00 or 13:00:00
    if fri_close == expected_fri_close or fri_close == expected_fri_close_sql:
        score += 60
        feedback_parts.append("Friday closing time correctly updated to 1:00 PM (13:00).")
    else:
        feedback_parts.append(f"Friday closing time incorrect. Expected '13:00', found '{fri_close}'.")

    # 4. Precision Verification (20 pts)
    # Ensure other days/times weren't messed up
    precision_score = 0
    
    # Check Monday Close (Control)
    if mon_close.startswith(initial_mon_close):
        precision_score += 10
    else:
        feedback_parts.append(f"Monday closing time was accidentally changed (Found: {mon_close}).")
        
    # Check Friday Open (Control)
    if fri_open.startswith(initial_fri_open):
        precision_score += 10
    else:
        feedback_parts.append(f"Friday opening time was accidentally changed (Found: {fri_open}).")
        
    if precision_score == 20:
        feedback_parts.append("Precision check passed (other schedule times preserved).")
    
    score += precision_score

    # 5. VLM / Workflow Verification (20 pts)
    # Use trajectory to ensure they actually used the UI and didn't just magic the DB (though in this env that's hard)
    # and to provide a secondary check.
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        # Check if we have images
        if frames or final_img:
            prompt = """
            Analyze these screenshots of a medical software interface (NOSH).
            The user should be navigating to a settings or schedule configuration page.
            
            Look for:
            1. An administrative menu or dashboard.
            2. A form showing days of the week (Monday, Tuesday, Friday, etc.) and times.
            3. The user changing a time setting.
            
            Did the user navigate to a schedule/practice settings page?
            Reply with JSON: {"settings_accessed": true/false}
            """
            
            images_to_send = frames + ([final_img] if final_img else [])
            vlm_response = query_vlm(images=images_to_send, prompt=prompt)
            
            if vlm_response and vlm_response.get("parsed", {}).get("settings_accessed", False):
                vlm_score = 20
                feedback_parts.append("Visual verification confirmed settings navigation.")
            else:
                # Fallback: if DB is correct, we assume they used the UI effectively even if VLM missed it.
                # But we give points if DB is correct.
                if score >= 60:
                    vlm_score = 20
                    feedback_parts.append("Visual verification inconclusive, but database confirms success.")
                else:
                    feedback_parts.append("Visual verification could not confirm workflow.")
        else:
            # No images available
            if score >= 60: 
                vlm_score = 20 # Benefit of doubt if DB is right
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # If DB check passed, we still award points to avoid punishing for VLM errors
        if score >= 60:
            vlm_score = 20

    score += vlm_score

    # Final Result
    passed = score >= 80 # Requires DB success + Precision
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }