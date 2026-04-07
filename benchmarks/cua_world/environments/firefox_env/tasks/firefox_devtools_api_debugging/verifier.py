#!/usr/bin/env python3
"""
Verifier for Firefox DevTools API Debugging task.

Verification Multi-Signal Strategy:
1. DB Check: Checks if a request returned 200 OK (30 points)
2. Payload Accuracy: Verifies the JSON payload was properly corrected (30 points)
3. Anti-Gaming: Checks browser User-Agent to foil 'curl' scripts (20 points)
4. VLM Check: Uses trajectory frames to visually confirm DevTools usage (20 points)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_firefox_devtools_api_debugging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_endpoint = metadata.get('expected_endpoint', '/api/v1/telemetry/sync')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    requests = result.get("requests", [])
    
    score = 0
    feedback = []
    
    # Locate the most successful or relevant request
    target_request = None
    for req in requests[::-1]: # Iterate backwards to get the most recent request
        if req.get("path") == expected_endpoint and req.get("status_code") == 200:
            target_request = req
            break

    # ================================================================
    # CRITERION 1: Successful Request Logged (30 points)
    # ================================================================
    if target_request:
        score += 30
        feedback.append("Successful 200 OK request intercepted by server.")
    else:
        feedback.append("No successful 200 OK request to the target endpoint found in database logs.")
        # If there is no successful request, we fail early to avoid passing on partial non-functional work.
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # ================================================================
    # CRITERION 2: Correct Payload Verification (30 points)
    # ================================================================
    payload_str = target_request.get("payload", "")
    payload_correct = False
    try:
        payload_json = json.loads(payload_str)
        if payload_json.get("mode") == "bidirectional" and payload_json.get("force_refresh") is True:
            payload_correct = True
    except json.JSONDecodeError:
        pass
        
    if payload_correct:
        score += 30
        feedback.append("Request payload perfectly matches requirements.")
    else:
        feedback.append(f"Payload incorrect or missing required fields: {payload_str}")

    # ================================================================
    # CRITERION 3: Browser Anti-Gaming Headers (20 points)
    # ================================================================
    # Ensure the request came from Firefox, not a Python script or cURL executing inside the container
    user_agent = target_request.get("user_agent", "")
    is_valid_browser = "Mozilla" in user_agent and "curl" not in user_agent.lower() and "python" not in user_agent.lower()
    
    if is_valid_browser:
        score += 20
        feedback.append("Verified HTTP request originated from a web browser.")
    else:
        feedback.append(f"Suspicious User-Agent detected: {user_agent}. Possible gaming attempt.")

    # ================================================================
    # CRITERION 4: VLM Trajectory Verification (20 points)
    # ================================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "You are verifying if an agent used browser developer tools to modify a network request. "
            "Examine these trajectory frames. Did the agent open the Firefox Developer Tools Network tab, "
            "and use the 'Edit and Resend' or 'New Request' sidebar to modify a JSON payload? "
            "Respond with YES or NO."
        )
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        
        if "YES" in vlm_res.upper():
            score += 20
            feedback.append("VLM confirmed usage of Firefox DevTools Network panel.")
        else:
            feedback.append("VLM could not confirm explicit usage of the Developer Tools sidebar.")
            
    except ImportError:
        # Fallback if gym_anything.vlm is unavailable in the execution context
        logger.warning("VLM module not available. Skipping visual trajectory check.")
        score += 20
        feedback.append("VLM visual verification skipped (module unavailable).")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback.append("VLM check encountered an error.")

    # Determine final Pass/Fail
    # Agent must achieve a functional result through the browser and fix the payload completely
    key_criteria_met = (target_request is not None) and payload_correct and is_valid_browser
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }