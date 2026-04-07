#!/usr/bin/env python3
"""
Verifier for enable_https_socioboard task.

Verification Strategy (Programmatic):
1. Apache listening on 443 (20 pts)
2. SSL Handshake Successful (20 pts)
3. Socioboard Served via HTTPS (curl returns 200/302 + Socioboard HTML) (40 pts)
   *This prevents gaming where the agent just enables default-ssl without fixing the DocumentRoot.*
4. Environment Config Updated (APP_URL=https://localhost) (20 pts)

Pass Threshold: 80 points (Must successfully serve the app over HTTPS, even if config is missed).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_https_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_url = metadata.get('expected_url', 'https://localhost')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result from environment: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Port 443 Open (20 points)
    if result.get('port_443_open', False):
        score += 20
        feedback_parts.append("Port 443 is open")
    else:
        feedback_parts.append("Port 443 is NOT open")

    # 2. SSL Handshake (20 points)
    if result.get('ssl_handshake', False):
        score += 20
        feedback_parts.append("SSL Handshake successful")
    else:
        feedback_parts.append("SSL Handshake failed")

    # 3. HTTPS Content Match (40 points)
    # Checks that curling https://localhost actually returns Socioboard, 
    # not just an empty Apache "It works!" page.
    status = result.get('https_status', '000')
    content_match = result.get('https_content_match', False)
    
    if content_match and status in ['200', '302', '301']:
        score += 40
        feedback_parts.append("Socioboard application successfully served over HTTPS")
    elif content_match:
        score += 20
        feedback_parts.append(f"HTTPS returned Socioboard content, but abnormal status: {status}")
    else:
        feedback_parts.append("HTTPS request did not return the Socioboard application (check DocumentRoot in VirtualHost)")

    # 4. Environment Config Updated (20 points)
    env_app_url = result.get('env_app_url', '')
    if expected_url in env_app_url:
        score += 20
        feedback_parts.append(f"APP_URL updated to {expected_url}")
    else:
        feedback_parts.append(f"APP_URL incorrect. Found: '{env_app_url}', Expected: '{expected_url}'")

    # Key criteria: They MUST have successfully configured Apache to serve the app over HTTPS.
    # A perfect score is 100. Minimum passing score is 80 (meaning they might have forgotten the .env file but got the server working).
    passed = score >= 80 and content_match

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }