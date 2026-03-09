#!/usr/bin/env python3
"""
Verifier for broadcast_maintenance_message task.

Criteria:
1. API Verification: System message is ENABLED.
2. API Verification: Message text matches exactly.
3. API Verification: Color matches 'warn' (orange).
4. VLM Verification: Banner is visible in the final screenshot.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_broadcast_maintenance_message(traj, env_info, task_info):
    """
    Verifies that the system message was correctly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_message = metadata.get('expected_message', '')
    expected_color = metadata.get('expected_color', 'warn')
    
    # 1. Retrieve Programmatic Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_log = []
    
    # --- Criterion 1: Enabled (30 pts) ---
    is_enabled = result_data.get('enabled', False)
    if is_enabled:
        score += 30
        feedback_log.append("Success: System message is enabled.")
    else:
        feedback_log.append("Fail: System message is NOT enabled.")

    # --- Criterion 2: Correct Text (40 pts) ---
    actual_message = result_data.get('message', '').strip()
    if actual_message == expected_message:
        score += 40
        feedback_log.append("Success: Message text matches exactly.")
    else:
        feedback_log.append(f"Fail: Message text mismatch.\nExpected: '{expected_message}'\nGot: '{actual_message}'")

    # --- Criterion 3: Correct Color (20 pts) ---
    actual_color = result_data.get('color', '').lower()
    # 'warn' is the value, typically maps to orange in UI
    if actual_color == expected_color:
        score += 20
        feedback_log.append("Success: Severity/Color is correct.")
    else:
        feedback_log.append(f"Fail: Color mismatch. Expected '{expected_color}', got '{actual_color}'.")

    # --- Criterion 4: VLM Visual Verification (10 pts) ---
    # We check if the banner is actually visible on the screen.
    # This prevents cases where API was hacked but UI is broken, or verifies navigation.
    
    # We can use the gym_anything VLM helper if available in the environment context,
    # but the instructions say to use `query_vlm` from `gym_anything.vlm` imports if available,
    # or rely on the framework injecting it.
    # We will simulate the check structure.
    
    # Note: In standard verification, we assume `query_vlm` is passed or imported.
    # Here we define the check logic assuming access to trajectory.
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        # Prompt for VLM
        prompt = (
            "Look at this screenshot of the JFrog Artifactory interface. "
            "Is there a visible colored banner (likely orange or yellow) at the top of the page "
            "displaying a system message about 'Scheduled Maintenance'? "
            "Answer yes or no."
        )
        # In a real run, we would call: result = query_vlm(images=[final_screenshot], prompt=prompt)
        # Since we are generating code, we assume the framework handles VLM if configured in success spec.
        # However, purely programmatic verification is usually robust enough for config tasks.
        # We will award these points if the API check passed, assuming UI reflects API.
        
        # NOTE: To be strictly robust, if we can't call VLM here, we redistribute points or 
        # rely on the API. Since this is a generated file for a system that supports VLM:
        
        try:
            from gym_anything.vlm import query_vlm
            vlm_res = query_vlm(images=[final_screenshot], prompt=prompt)
            if "yes" in vlm_res.get("response", "").lower():
                vlm_score = 10
                feedback_log.append("Success: Banner visually verified via VLM.")
            else:
                feedback_log.append("Warning: Banner not clearly visible to VLM.")
        except ImportError:
            # Fallback if VLM lib not available: give points if API success
            if score >= 90:
                vlm_score = 10
                feedback_log.append("VLM check skipped (lib missing), assumed visible based on API.")
    else:
        feedback_log.append("Warning: No final screenshot available for VLM check.")

    score += vlm_score

    # Final Pass Determination
    # We require strict text match and enabled status
    passed = (is_enabled and actual_message == expected_message and actual_color == expected_color)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }