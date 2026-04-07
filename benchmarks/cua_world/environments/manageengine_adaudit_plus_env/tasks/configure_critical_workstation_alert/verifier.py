#!/usr/bin/env python3
"""
Verifier for configure_critical_workstation_alert task.

Verification Strategy:
1. DB Check: Confirm an alert profile named "SWIFT Terminal Access" exists in the DB.
2. VLM Check: Analyze trajectory/screenshots to verify:
   - Alert Name: "SWIFT Terminal Access"
   - Filter: "Client Machine Name" contains "SWIFT-TERM-01"
   - Category: Logon Audit / Success
   - Severity: High/Critical

Score Distribution:
- Database Record Exists: 20 pts
- VLM: Correct Profile Name visible: 20 pts
- VLM: Correct Machine Filter (SWIFT-TERM-01) visible: 40 pts
- VLM: Correct Severity/Category: 20 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_critical_workstation_alert(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from container
    # The Windows path C:\workspace... maps to a location we can copy from.
    # We assume copy_from_env handles the path conversion or we use the absolute path in the container.
    # For Windows containers, paths might be tricky. Usually 'C:/workspace/...' works.
    
    task_result_path = "C:/workspace/tasks/configure_critical_workstation_alert/task_result.json"
    local_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    db_check_passed = False
    
    try:
        copy_from_env(task_result_path, local_temp.name)
        with open(local_temp.name, 'r') as f:
            result_data = json.load(f)
            db_check_passed = result_data.get("alert_found_in_db", False)
    except Exception as e:
        logger.warning(f"Could not load task result from container: {e}")
        # Proceed with VLM only if file copy fails (fallback)
    finally:
        if os.path.exists(local_temp.name):
            os.unlink(local_temp.name)

    # 2. VLM Verification
    # We need to see the configuration screen where the filter is set.
    # The final screenshot might just be the list of alerts.
    # Trajectory analysis is best to catch the "Edit/Create" form.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    images_to_check = frames + ([final_shot] if final_shot else [])
    
    if not images_to_check:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}

    prompt = """
    You are verifying an IT automation task in ManageEngine ADAudit Plus.
    The goal was to create a specific alert profile.
    
    Look at the provided screenshots of the user interface.
    Search for a form or list showing an Alert Profile configuration.
    
    Verify the following details:
    1. PROFILE NAME: Is there an alert named "SWIFT Terminal Access"?
    2. FILTER CRITERIA: Is there a filter for "Client Machine Name" (or Workstation) containing "SWIFT-TERM-01"?
    3. CATEGORY: Is it related to "Logon Audit" or "User Logon"?
    4. SEVERITY: Is the severity set to "High" or "Critical"?
    
    Return a JSON object:
    {
        "profile_name_correct": boolean,
        "machine_filter_correct": boolean,
        "category_correct": boolean,
        "severity_correct": boolean,
        "reasoning": "string explanation"
    }
    """
    
    vlm_response = query_vlm(images=images_to_check, prompt=prompt)
    
    vlm_data = {}
    if vlm_response and 'result' in vlm_response:
        # Assuming query_vlm returns a dict with 'result' containing the text or parsed json
        # Adjust parsing based on actual vlm implementation
        try:
            # If the VLM returns a string, try to parse JSON
            import re
            json_match = re.search(r'\{.*\}', vlm_response['result'], re.DOTALL)
            if json_match:
                vlm_data = json.loads(json_match.group(0))
        except:
            logger.warning("Failed to parse VLM response")

    # If parsing failed or structure different, defaults to False
    profile_name_ok = vlm_data.get("profile_name_correct", False)
    machine_filter_ok = vlm_data.get("machine_filter_correct", False)
    category_ok = vlm_data.get("category_correct", False)
    severity_ok = vlm_data.get("severity_correct", False)

    # 3. Calculate Score
    score = 0
    feedback_items = []

    # Criterion 1: Database or VLM confirms Name (20 pts)
    if db_check_passed or profile_name_ok:
        score += 20
        feedback_items.append("Alert Profile created with correct name.")
    else:
        feedback_items.append("Alert Profile 'SWIFT Terminal Access' not found.")

    # Criterion 2: Machine Filter (CRITICAL) (40 pts)
    # Only VLM can reliably check the filter criteria inside the UI
    if machine_filter_ok:
        score += 40
        feedback_items.append("Correct workstation filter (SWIFT-TERM-01) detected.")
    else:
        feedback_items.append("Workstation filter 'SWIFT-TERM-01' NOT detected in screenshots.")

    # Criterion 3: Severity (20 pts)
    if severity_ok:
        score += 20
        feedback_items.append("Severity set correctly.")

    # Criterion 4: Category/Context (20 pts)
    if category_ok:
        score += 20
        feedback_items.append("Correct category selected.")

    # Pass Condition
    # Must have the name AND the filter correct.
    passed = (score >= 60) and machine_filter_ok and (db_check_passed or profile_name_ok)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items)
    }