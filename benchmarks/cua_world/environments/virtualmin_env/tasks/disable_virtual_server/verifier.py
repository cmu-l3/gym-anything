#!/usr/bin/env python3
"""
Verifier for disable_virtual_server task.

Scoring Criteria:
1. Domain still exists (20 pts) - CRITICAL (anti-delete check)
2. Domain is disabled (40 pts)
3. Web service inactive (15 pts)
4. Home directory preserved (10 pts)
5. Disable reason recorded matches expectations (15 pts)

Total: 100 pts
Pass Threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_virtual_server(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_reason_keywords', ["4781", "abuse", "phishing"])

    # Load result from container
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

    score = 0
    feedback_parts = []

    # 1. Domain Exists (20 pts)
    # This is critical. If they deleted the domain, they fail heavily.
    domain_exists = result.get('domain_exists', False)
    if domain_exists:
        score += 20
        feedback_parts.append("Domain preserved (not deleted)")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "CRITICAL FAIL: Domain was deleted instead of disabled. Task requires disabling to preserve evidence."
        }

    # 2. Domain Disabled (40 pts)
    is_disabled = result.get('is_disabled', False)
    if is_disabled:
        score += 40
        feedback_parts.append("Domain successfully disabled")
    else:
        feedback_parts.append("Domain is still active (not disabled)")

    # 3. Web Service Inactive (15 pts)
    # If disabled, we expect non-200 or 200 but NOT the original content
    web_code = result.get('web_status_code', "000")
    marker_found = result.get('web_content_marker_found', False)
    
    if marker_found:
        feedback_parts.append(f"Web service still serving original content (Code: {web_code})")
    else:
        score += 15
        feedback_parts.append(f"Web service inactive/changed (Code: {web_code})")

    # 4. Home Directory Preserved (10 pts)
    home_dir_exists = result.get('home_dir_exists', False)
    if home_dir_exists:
        score += 10
        feedback_parts.append("Data directory preserved")
    else:
        feedback_parts.append("Home directory missing")

    # 5. Disable Reason (15 pts)
    reason = result.get('disable_reason', "").lower()
    matches = sum(1 for k in expected_keywords if k.lower() in reason)
    
    if matches >= 2:
        score += 15
        feedback_parts.append("Disable reason recorded correctly")
    elif matches >= 1:
        score += 10
        feedback_parts.append("Disable reason partially recorded")
    elif reason:
        score += 5
        feedback_parts.append("Disable reason provided but generic")
    else:
        feedback_parts.append("No disable reason recorded")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }