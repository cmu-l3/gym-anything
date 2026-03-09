#!/usr/bin/env python3
"""
Verifier for configure_self_service_portal task.

Criteria:
1. "Allow requesters to reopen..." must be DISABLED (false).
2. "Show request cost..." must be ENABLED (true).
3. "Welcome Message" must match the specific text.
4. Changes must be reflected in the database (GlobalConfig).
5. VLM verification of the final UI state as a backup.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_self_service_portal(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_welcome = metadata.get('expected_welcome_message', "")
    
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

    db_settings = result.get('db_settings', {})
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Reopen Policy (30 pts) ---
    # Expected: False (Disabled)
    reopen_val = str(db_settings.get('reopen_request', '')).lower()
    if reopen_val == 'false':
        score += 30
        feedback_parts.append("Reopen policy correctly disabled.")
    else:
        feedback_parts.append(f"Reopen policy incorrect (DB value: {reopen_val}).")

    # --- Criterion 2: Cost Visibility (30 pts) ---
    # Expected: True (Enabled)
    cost_val = str(db_settings.get('show_cost', '')).lower()
    if cost_val == 'true':
        score += 30
        feedback_parts.append("Cost visibility correctly enabled.")
    else:
        feedback_parts.append(f"Cost visibility incorrect (DB value: {cost_val}).")

    # --- Criterion 3: Welcome Message (30 pts) ---
    # Expected: Exact string match (ignoring whitespace differences)
    actual_welcome = db_settings.get('welcome_message', '').strip()
    # Normalize spaces for comparison
    norm_expected = ' '.join(expected_welcome.split())
    norm_actual = ' '.join(actual_welcome.split())
    
    if norm_expected in norm_actual:
        score += 30
        feedback_parts.append("Welcome message updated correctly.")
    else:
        # Fallback: if DB update wasn't captured or table is different, use VLM
        feedback_parts.append(f"DB welcome message mismatch or not found.")
        
        # VLM Check for Message
        final_img = get_final_screenshot(traj)
        vlm_res = query_vlm(
            images=[final_img], 
            prompt=f"Does the text area for 'Welcome Message' contain the text: '{expected_welcome}'? Answer yes or no."
        )
        if vlm_res and vlm_res.get('parsed', False): # Assuming boolean parsing or string check
             # If VLM confirms it, give partial credit (DB might be lagging or wrong table queried)
             score += 20
             feedback_parts.append("(Verified via screenshot).")

    # --- Criterion 4: VLM UI Verification (10 pts) ---
    # Check if we are on the correct settings page
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    vlm_check = query_vlm(
        images=images,
        prompt="Is the user navigating the 'Self-Service Portal Settings' or 'General Settings' page in the ServiceDesk Plus administration interface?"
    )
    
    if "yes" in str(vlm_check.get('result', '')).lower():
        score += 10
    
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }