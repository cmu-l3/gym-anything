#!/usr/bin/env python3
"""
Verifier for modify_device_properties task.

Checks:
1. Device Display Name matches expected value.
2. Device Description matches expected value.
3. Device Location matches expected value (if applicable).
4. Changes were actually applied (Final != Initial).
5. Device is still present and not deleted.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_device_properties(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_display_name = metadata.get("expected_display_name", "Ubuntu-SIEM-Primary")
    expected_description = metadata.get("expected_description", "Primary SIEM collection server for East data center")
    expected_location = metadata.get("expected_location", "DC-East-Rack-A3")

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    final_state = result.get("final_state", {})
    initial_state = result.get("initial_state", {})
    
    # If final state is empty, device might have been deleted or API failed
    if not final_state:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not find the localhost device in final state. It may have been deleted or API failed."
        }

    score = 0
    feedback_parts = []
    
    # 1. Check Display Name (35 pts)
    actual_name = final_state.get("display_name", "")
    if actual_name == expected_display_name:
        score += 35
        feedback_parts.append("Display Name updated correctly")
    else:
        feedback_parts.append(f"Display Name incorrect (Expected: '{expected_display_name}', Got: '{actual_name}')")

    # 2. Check Description (25 pts)
    actual_desc = final_state.get("description", "")
    # Allow loose matching for description (ignoring case or minor whitespace)
    if expected_description.lower() in actual_desc.lower():
        score += 25
        feedback_parts.append("Description updated correctly")
    else:
        feedback_parts.append(f"Description incorrect or missing")

    # 3. Check Location (15 pts)
    # Location field might not exist in all versions of ELA. 
    # If the API doesn't return it, we might be lenient if other fields match.
    actual_loc = final_state.get("location", "")
    if expected_location.lower() in actual_loc.lower():
        score += 15
        feedback_parts.append("Location updated correctly")
    elif not actual_loc and "location" not in final_state:
        # Field not returned by API - Give points if other things passed to avoid punishing for version diffs
        score += 15
        feedback_parts.append("Location field not available in API (Skipped)")
    else:
        feedback_parts.append(f"Location incorrect (Expected: '{expected_location}', Got: '{actual_loc}')")

    # 4. Check Change Detection (15 pts)
    # Ensure it's not just the initial state (anti-gaming)
    init_name = initial_state.get("display_name", "")
    if actual_name != init_name and actual_name == expected_display_name:
        score += 15
        feedback_parts.append("Verified change from initial state")
    elif actual_name == init_name:
        feedback_parts.append("No change detected from initial state")

    # 5. Device Active/Status (10 pts)
    # We want to ensure the agent didn't break logging
    if final_state.get("ip"):
        score += 10
        feedback_parts.append("Device is still present")

    # VLM Verification (Fallback/Bonus logic could go here, but we rely on API for this data-heavy task)
    # We'll use the final screenshot just to confirm UI state if API fails, but primarily API.

    passed = score >= 60 and (actual_name == expected_display_name)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }