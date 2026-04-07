#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rest_api_patient_lookup(traj, env_info, task_info):
    """
    Verify the REST API Patient Lookup task.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Channel Exists and Started (10 pts)
    if result.get('channel_id') and result.get('channel_status') in ['STARTED', 'RUNNING']:
        score += 10
        feedback.append("Channel created and started.")
    elif result.get('channel_id'):
        score += 5
        feedback.append(f"Channel created but status is {result.get('channel_status')}.")
    else:
        feedback.append("Channel not found.")

    # 2. Port Listening (10 pts)
    if result.get('is_listening'):
        score += 10
        feedback.append("Port 6670 is listening.")
    else:
        feedback.append("Port 6670 is NOT listening.")

    # 3. Positive Test (25 pts)
    pos = result.get('positive_test', {})
    if pos.get('success'):
        score += 25
        feedback.append("Positive test passed (HTTP 200 + Correct Data).")
    else:
        feedback.append(f"Positive test failed. Code: {pos.get('http_code')}, Body: {pos.get('body_preview')}.")

    # 4. Negative Test (20 pts)
    neg = result.get('negative_test', {})
    if neg.get('success'):
        score += 20
        feedback.append("Negative test passed (HTTP 404).")
    elif neg.get('http_code') == '200':
        feedback.append("Negative test failed: Returned HTTP 200 instead of 404.")
    else:
        feedback.append(f"Negative test failed. Code: {neg.get('http_code')}.")

    # 5. Dynamic Test (35 pts) - Critical for ensuring DB lookup
    dyn = result.get('dynamic_test', {})
    if dyn.get('success'):
        score += 35
        feedback.append("Dynamic DB lookup verified (Real-time data access).")
    else:
        feedback.append("Dynamic DB lookup failed. Agent might be hardcoding responses or DB connection is broken.")

    # Pass Threshold
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }