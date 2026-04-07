#!/usr/bin/env python3
"""
Verifier for enable_local_https_nginx task.

Verifies:
1. Port 443 is accessible and serving HTTPS.
2. The SSL certificate matches the specific file provided in setup (proof of correct volume mount).
3. The content served is correct.
4. The container is running.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_local_https_nginx(traj, env_info, task_info):
    # Setup copy
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
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Container Running (10 pts)
    if result.get('container_running', False):
        score += 10
        feedback_parts.append("Container running (+10)")
    else:
        feedback_parts.append("Container NOT running")

    # 2. Port 443 / HTTPS Accessible (20 pts)
    # 3. SSL Handshake Success (30 pts)
    # We combine these based on the export script's checks
    if result.get('https_accessible', False):
        # If accessible via https://localhost, both port and handshake are good
        score += 50 
        feedback_parts.append("HTTPS accessible on port 443 (+50)")
    else:
        # Check if it was just a 404 or something vs connection refused
        http_code = result.get('http_code', '000')
        if http_code != '000':
            score += 20 # Port is open, but maybe content or cert error
            feedback_parts.append(f"Port 443 open but returned HTTP {http_code} (+20)")
        else:
            feedback_parts.append("Port 443 unreachable or handshake failed")

    # 4. Correct Certificate (25 pts)
    if result.get('cert_match', False):
        score += 25
        feedback_parts.append("Correct certificate served (+25)")
    else:
        served = result.get('served_fingerprint', 'none')
        feedback_parts.append(f"Incorrect/Missing certificate (Served fingerprint: {served})")

    # 5. Content Served (15 pts)
    if result.get('content_match', False):
        score += 15
        feedback_parts.append("Correct content served (+15)")
    else:
        feedback_parts.append("Content check failed")

    # Penalties or sanity checks
    # If they passed HTTPS check but used the wrong cert, they might have generated a new one 
    # instead of mounting the existing one. We penalize that by strictly requiring cert_match for full pass.
    
    pass_threshold = 75
    passed = (score >= pass_threshold) and result.get('cert_match', False) and result.get('https_accessible', False)

    if not result.get('cert_match', False) and result.get('https_accessible', False):
        feedback_parts.append("FAIL: You must use the PROVIDED certificates, not generate new ones.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }