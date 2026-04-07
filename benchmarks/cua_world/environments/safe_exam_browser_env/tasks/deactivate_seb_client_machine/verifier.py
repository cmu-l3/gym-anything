#!/usr/bin/env python3
"""
Verifier for deactivate_seb_client_machine task.

Evaluation Strategy (Multiple Signals):
1. Database State: Checks if 'Loaner-Laptop-22' exists and its active status is '0' (False).
2. Trajectory VLM: Examines the UI progression to ensure the agent actively navigated and modified the configuration.
3. Anti-Gaming: Enforces file creation and reasonable timestamps.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deactivate_client(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    feedback_parts = []
    score = 0

    # 1. Retrieve the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load DB results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Database Verification (Primary Signal)
    cc_info = result.get('seb_client_config', {})
    node_info = result.get('configuration_node', {})

    db_target_exists = cc_info.get('exists') or node_info.get('exists')
    
    # Active status is returned as string '1' (True) or '0' (False) from MariaDB
    cc_deactivated = cc_info.get('active_status') == '0'
    node_deactivated = node_info.get('active_status') == '0'
    
    db_deactivated = (cc_info.get('exists') and cc_deactivated) or (node_info.get('exists') and node_deactivated)

    if db_target_exists:
        score += 20
        feedback_parts.append("Target configuration located in DB")
        
        if db_deactivated:
            score += 40
            feedback_parts.append("DB Status: Successfully deactivated (Active=0)")
        else:
            feedback_parts.append("DB Status: Configuration is still Active (Failed)")
    else:
        feedback_parts.append("DB Status: Target configuration 'Loaner-Laptop-22' not found")

    # 3. VLM Trajectory Verification (Secondary Signal)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames
        
        if images:
            prompt = (
                "You are evaluating a security operation in Safe Exam Browser Server.\n"
                "The agent's task is to deactivate a client configuration named 'Loaner-Laptop-22'.\n"
                "Look at these trajectory screenshots and determine:\n"
                "1. Did the agent navigate to the Client/Connection Configurations menu?\n"
                "2. Did the agent edit or interact with 'Loaner-Laptop-22'?\n"
                "3. Did the agent successfully uncheck the 'Active' status and save?\n"
                "Reply with a JSON dictionary containing boolean keys: 'navigated', 'interacted_with_target', 'deactivated_and_saved'."
            )
            vlm_response = query_vlm(images=images, prompt=prompt)
            
            if vlm_response and hasattr(vlm_response, 'get'):
                # Extract values, defaulting to False
                parsed = vlm_response.get("parsed", {})
                if not isinstance(parsed, dict):
                    import ast
                    try:
                        parsed = ast.literal_eval(str(parsed))
                    except:
                        parsed = {}

                if parsed.get('navigated', False):
                    vlm_score += 10
                    feedback_parts.append("VLM: Navigation confirmed")
                if parsed.get('interacted_with_target', False):
                    vlm_score += 10
                    feedback_parts.append("VLM: Interaction with target confirmed")
                if parsed.get('deactivated_and_saved', False):
                    vlm_score += 20
                    feedback_parts.append("VLM: Deactivation save confirmed")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM fails but DB is perfectly correct, grant fallback points
        if db_deactivated:
            vlm_score += 40
            feedback_parts.append("VLM fallback: Awarded points based on perfect DB state")

    score += vlm_score

    # 4. Anti-gaming check
    if result.get('duration_seconds', 0) < 5:
        score = 0
        feedback_parts = ["Task completed suspiciously fast (Gaming detected)"]

    passed = score >= 70 and db_deactivated
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }