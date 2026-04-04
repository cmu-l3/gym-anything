#!/usr/bin/env python3
"""
Verifier for test_offline_mode_handling task.

SCORING CRITERIA:
1. Wi-Fi Restored (CRITICAL): 40 pts
   - If device is offline at end, massive penalty or fail.
2. Report Created: 20 pts
   - File exists and was created during task.
3. Report Content: 20 pts
   - Contains keywords indicating an error was observed.
4. VLM Verification: 20 pts
   - Visible attempt to search while offline (error dialog/spinner).
   - Visible interaction with Wi-Fi settings.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_test_offline_mode_handling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_keywords', ["error", "network", "offline", "fail"])

    # Setup temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # 1. Fetch JSON result
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        # 2. Fetch Report Content (full file) if it exists
        report_content = ""
        if result.get("report_exists"):
            try:
                copy_from_env("/sdcard/offline_test_report.txt", temp_report.name)
                with open(temp_report.name, 'r', errors='ignore') as f:
                    report_content = f.read().lower()
            except Exception as e:
                logger.warning(f"Could not copy report file: {e}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    score = 0
    feedback_parts = []
    passed = False

    # --- CRITERION 1: Network Connectivity Restored (40 pts) ---
    # This is a critical requirement.
    is_online = result.get("network_online", False)
    wifi_setting = str(result.get("wifi_enabled_setting", "0")).strip()
    
    # Accept either ping success OR settings saying wifi is on (1)
    if is_online or wifi_setting == "1":
        score += 40
        feedback_parts.append("✅ Wi-Fi restored successfully")
    else:
        feedback_parts.append("❌ Critical: Device left offline (Wi-Fi not restored)")
        # If they didn't restore Wi-Fi, it's a major failure of the task description
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Failed: You must restore Wi-Fi connectivity before finishing. " + " | ".join(feedback_parts)
        }

    # --- CRITERION 2: Report Existence & Timing (20 pts) ---
    if result.get("report_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("✅ Report file created")
    elif result.get("report_exists"):
        score += 10
        feedback_parts.append("⚠️ Report exists but timestamp suggests pre-existence")
    else:
        feedback_parts.append("❌ No report file found")

    # --- CRITERION 3: Report Content (20 pts) ---
    if report_content:
        found_keywords = [k for k in required_keywords if k in report_content]
        if found_keywords:
            score += 20
            feedback_parts.append(f"✅ Report content valid (found: {', '.join(found_keywords)})")
        else:
            score += 5
            feedback_parts.append("⚠️ Report content unclear (no error keywords found)")
    else:
        feedback_parts.append("❌ Report is empty or missing")

    # --- CRITERION 4: VLM Trajectory Verification (20 pts) ---
    # We want to see:
    # 1. Agent interacting with settings/quick settings to turn off wifi
    # 2. Agent seeing an error in the app
    
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    Review this sequence of screenshots from an Android device. 
    The user was asked to:
    1. Turn OFF Wi-Fi.
    2. Try to search for a flight in 'Flight Crew View' app.
    3. Document the error.
    4. Turn ON Wi-Fi.

    Look for:
    - Evidence of Wi-Fi being disabled (airplane mode icon, wifi slash icon, or Quick Settings interaction).
    - Evidence of the App showing an error, 'No Connection', loading spinner, or empty state.
    - Evidence of Wi-Fi being re-enabled at the end.

    JSON Response:
    {
        "wifi_disabled_visible": true/false,
        "app_error_visible": true/false,
        "wifi_enabled_at_end": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("wifi_disabled_visible"):
            vlm_score += 10
            feedback_parts.append("✅ VLM confirmed Wi-Fi toggle")
        
        if parsed.get("app_error_visible"):
            vlm_score += 10
            feedback_parts.append("✅ VLM confirmed app error observed")
            
        # We already checked wifi_enabled programmatically, so we use VLM just for the workflow steps
    
    score += vlm_score

    # Final Pass/Fail Check
    # Must have restored wifi (checked above) AND created report AND got reasonable score
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }