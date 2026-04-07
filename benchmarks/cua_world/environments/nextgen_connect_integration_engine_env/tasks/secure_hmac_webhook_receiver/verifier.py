#!/usr/bin/env python3
"""
Verifier for secure_hmac_webhook_receiver task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_hmac_webhook_receiver(traj, env_info, task_info):
    """
    Verifies that the Secure HMAC Webhook Receiver channel is correctly implemented.
    
    Scoring Criteria (Total 100):
    1. Infrastructure (30 pts):
       - Channel exists and is deployed (10)
       - Port is 6675 (10)
       - Output directory config (inferred from successful write) (10)
    
    2. Security Logic (70 pts):
       - Valid Request: Accepted and file created (30)
       - Tampered Request: Rejected/Filtered (no new file) (20)
       - Unsigned Request: Rejected/Filtered (no new file) (20)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Infrastructure Checks
    if result.get("channel_found", False):
        score += 5
        feedback_parts.append("Channel 'CloudBook_Webhook' created.")
        
        status = result.get("channel_status", "UNKNOWN")
        if status in ["STARTED", "DEPLOYED"]:
            score += 5
            feedback_parts.append("Channel is deployed/started.")
        else:
            feedback_parts.append(f"Channel status is {status} (expected STARTED).")
            
        if result.get("port_correct", False):
            score += 10
            feedback_parts.append("Port 6675 configured correctly.")
        else:
            feedback_parts.append("Port configuration incorrect (expected 6675).")
            
        if result.get("filter_exists", False):
             feedback_parts.append("Source filter logic detected.")
        else:
             feedback_parts.append("No source filter logic detected.")
    else:
        feedback_parts.append("Channel 'CloudBook_Webhook' not found.")

    # 2. Functional Security Tests
    tests = result.get("tests", {})
    
    # Valid Request
    valid = tests.get("valid_req", {})
    if valid.get("passed", False):
        score += 30
        feedback_parts.append("SECURITY PASS: Valid HMAC signature accepted and file written.")
        # Implicitly confirm output directory config works
        score += 10 
    else:
        feedback_parts.append("SECURITY FAIL: Valid HMAC signature did not produce an output file.")

    # Tampered Request
    tampered = tests.get("tampered_req", {})
    if tampered.get("passed", False):
        score += 20
        feedback_parts.append("SECURITY PASS: Tampered payload rejected (no file created).")
    else:
        feedback_parts.append("SECURITY FAIL: Tampered payload was processed (file created).")

    # Unsigned Request
    unsigned = tests.get("unsigned_req", {})
    if unsigned.get("passed", False):
        score += 20
        feedback_parts.append("SECURITY PASS: Missing header rejected (no file created).")
    else:
        feedback_parts.append("SECURITY FAIL: Missing header was processed (file created).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }