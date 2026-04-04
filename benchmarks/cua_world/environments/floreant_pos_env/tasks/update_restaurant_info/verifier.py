#!/usr/bin/env python3
"""
Verifier for update_restaurant_info task.
Checks if the restaurant configuration in the Derby database matches the expected values.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_restaurant_info(traj, env_info, task_info):
    """
    Verify restaurant info update.
    
    Criteria:
    1. Restaurant Name matches "Bayview Grill & Taphouse" (25 pts)
    2. Address matches "782 Shoreline Boulevard" (25 pts)
    3. Zip Code matches "94301" (25 pts)
    4. Telephone matches "6508520194" (25 pts)
    
    Anti-gaming:
    - Checks that data actually changed from baseline.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Get Metadata / Expected Values
    metadata = task_info.get('metadata', {})
    exp_name = metadata.get('expected_name', "Bayview Grill & Taphouse")
    exp_address = metadata.get('expected_address', "782 Shoreline Boulevard")
    exp_zip = metadata.get('expected_zip', "94301")
    exp_phone = metadata.get('expected_phone', "6508520194")

    # Get Actual Values
    final_data = result.get('final', {})
    act_name = final_data.get('name', '').strip()
    act_address = final_data.get('address', '').strip()
    act_zip = final_data.get('zip_code', '').strip()
    act_phone = final_data.get('telephone', '').strip()

    score = 0
    feedback = []

    # 1. Verify Name (25 pts)
    # Allow case-insensitive check and ignore minor whitespace
    if act_name.lower() == exp_name.lower():
        score += 25
        feedback.append("Name: Correct")
    elif "bayview" in act_name.lower() and "grill" in act_name.lower():
        score += 15
        feedback.append(f"Name: Partial match ('{act_name}')")
    else:
        feedback.append(f"Name: Incorrect ('{act_name}')")

    # 2. Verify Address (25 pts)
    if act_address.lower() == exp_address.lower():
        score += 25
        feedback.append("Address: Correct")
    elif "782 shoreline" in act_address.lower():
        score += 15
        feedback.append(f"Address: Partial match ('{act_address}')")
    else:
        feedback.append(f"Address: Incorrect ('{act_address}')")

    # 3. Verify Zip (25 pts)
    if act_zip == exp_zip:
        score += 25
        feedback.append("Zip: Correct")
    else:
        feedback.append(f"Zip: Incorrect ('{act_zip}')")

    # 4. Verify Phone (25 pts)
    # Normalize phone (remove dashes/spaces)
    norm_act_phone = "".join(filter(str.isdigit, act_phone))
    norm_exp_phone = "".join(filter(str.isdigit, exp_phone))
    
    if norm_act_phone == norm_exp_phone:
        score += 25
        feedback.append("Phone: Correct")
    elif norm_exp_phone in norm_act_phone: # Allow if they added country code or extra formatting
        score += 25
        feedback.append("Phone: Correct (format variance accepted)")
    else:
        feedback.append(f"Phone: Incorrect ('{act_phone}')")

    # 5. Anti-Gaming / Sanity Check
    baseline = result.get('baseline', {})
    base_name = baseline.get('name', '')
    
    # If the score is high but the name hasn't changed from baseline, something is wrong
    # (Unless the baseline happened to match expected, which is unlikely for a rebrand task)
    if score > 0 and act_name == base_name and act_name != exp_name:
        score = 0
        feedback.append("ANTI-GAMING: Data matches baseline (no changes made).")

    # Check if app was running
    if not result.get('app_was_running', False):
        feedback.append("Warning: App was not running at end of task.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }