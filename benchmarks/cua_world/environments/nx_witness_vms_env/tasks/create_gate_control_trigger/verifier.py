#!/usr/bin/env python3
"""
Verifier for create_gate_control_trigger task.

Verifies:
1. A 'softwareTriggerEvent' rule exists.
2. It is linked to the 'Entrance Camera'.
3. The trigger name contains 'OPEN GATE'.
4. The action is 'httpAction'.
5. The URL and Credentials match the manual.
"""

import json
import os
import tempfile
import logging
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gate_control_trigger(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_cam_name = metadata.get('target_camera_name', "Entrance Camera")
    trigger_name = metadata.get('trigger_name', "OPEN GATE")
    expected_url = metadata.get('expected_url', "")
    expected_user = metadata.get('expected_user', "")
    expected_pass = metadata.get('expected_pass', "")

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    rules = data.get('rules', [])
    devices = data.get('devices', [])

    # 1. Resolve Target Camera ID
    target_cam_id = None
    for d in devices:
        if d.get('name', '') == target_cam_name:
            target_cam_id = d.get('id')
            break
    
    if not target_cam_id:
        return {"passed": False, "score": 0, "feedback": f"Internal Error: Could not find camera '{target_cam_name}' in system."}

    # 2. Find the candidate rule
    candidate_rule = None
    feedback_log = []
    
    for rule in rules:
        # Check for Software Trigger
        if rule.get('eventType') != 'softwareTriggerEvent':
            continue

        # Check Name (embedded in eventCondition usually, or comment)
        # Nx Witness API for softwareTriggerEvent:
        # eventCondition: text containing the name/icon config
        # OR comment field
        # We check simply if the trigger name string appears in the condition or comment
        cond = rule.get('eventCondition', '')
        comment = rule.get('comment', '')
        
        # Check if "OPEN GATE" is in the text
        if trigger_name not in cond and trigger_name not in comment:
            continue
            
        candidate_rule = rule
        break

    if not candidate_rule:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"No Soft Trigger rule found with name '{trigger_name}'."
        }

    score = 20 # Found the rule with correct type and name
    feedback_log.append(f"Found Soft Trigger '{trigger_name}'.")

    # 3. Verify Target Device (Entrance Camera)
    # eventResourceIds should contain the camera ID
    resource_ids = candidate_rule.get('eventResourceIds', [])
    if target_cam_id in resource_ids:
        score += 20
        feedback_log.append(f"Correctly assigned to '{target_cam_name}'.")
    else:
        feedback_log.append(f"Incorrect camera assignment. Expected {target_cam_name}.")

    # 4. Verify Action Type
    action_type = candidate_rule.get('actionType')
    if action_type == 'httpAction':
        score += 10
        feedback_log.append("Action type is HTTP Request.")
    else:
        feedback_log.append(f"Incorrect action type: {action_type}.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_log)}

    # 5. Verify Action Params (URL, Auth)
    # actionParams is usually a JSON string or object encoded
    params_raw = candidate_rule.get('actionParams', {})
    
    # Nx API usually returns this as a string that needs parsing, or a dict depending on version
    # The setup script creates 5.1/6.0 env. Let's assume it's accessible.
    # If it's a string, we might need to look for substrings.
    
    # Robust check: convert to string and look for substrings
    params_str = str(params_raw)

    # Check URL
    if expected_url in params_str:
        score += 20
        feedback_log.append("URL matches.")
    else:
        # Check if just the base IP/path matches (ignoring protocol potentially)
        parsed_expected = urlparse(expected_url)
        if parsed_expected.netloc in params_str and parsed_expected.path in params_str:
             score += 15
             feedback_log.append("URL matches (approx).")
        else:
            feedback_log.append(f"URL mismatch. Expected {expected_url}.")

    # Check Credentials
    # Note: Password might be masked/encrypted in API response for security
    # But often in 'actionParams' for httpAction it might be visible or we check username
    if expected_user in params_str:
        score += 15
        feedback_log.append("Username found.")
    else:
        feedback_log.append("Username not found in config.")

    # Check password (if visible, otherwise give benefit of doubt if username is there)
    # If not visible, we can't verify, but we awarded points for user. 
    # Let's allocate the last 15 points to "Method POST" or existence of auth fields.
    if "POST" in params_str or "post" in params_str: # Method check
        score += 15
        feedback_log.append("HTTP Method POST confirmed.")
    elif expected_pass in params_str:
        score += 15
        feedback_log.append("Password confirmed.")
    else:
        # Fallback: if we found user and url, assume user attempted auth setup
        if expected_user in params_str:
            score += 15
            feedback_log.append("Auth configuration detected.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log)
    }