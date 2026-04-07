#!/usr/bin/env python3
"""
Verifier for Secure Socket Proxy task.

Criteria:
1. Socket Removed (20 pts): Monitor container must NOT have /var/run/docker.sock mounted.
2. Proxy Created (20 pts): Proxy container MUST have /var/run/docker.sock mounted.
3. Connectivity (20 pts): Monitor can GET /containers/json via proxy (HTTP 200).
4. Method Restriction (30 pts): Proxy blocks POST requests (HTTP 403/405).
5. Clean Logs (10 pts): Monitor logs show success.

Pass Threshold: 70 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_socket_proxy_nginx(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    # 1. Socket Removed from Monitor (20 pts)
    monitor_running = result.get('monitor_running', False)
    monitor_has_socket = result.get('monitor_has_socket', True)
    
    if monitor_running and not monitor_has_socket:
        score += 20
        feedback_parts.append("Monitor socket removed (Correct)")
    elif not monitor_running:
        feedback_parts.append("Monitor service not running")
    else:
        feedback_parts.append("Monitor still has insecure socket mount")

    # 2. Proxy Created & Configured (20 pts)
    proxy_running = result.get('proxy_running', False)
    proxy_has_socket = result.get('proxy_has_socket', False)
    
    if proxy_running and proxy_has_socket:
        score += 20
        feedback_parts.append("Proxy service running with socket")
    elif not proxy_running:
        feedback_parts.append("Proxy service not found")
    else:
        feedback_parts.append("Proxy running but missing socket mount")

    # 3. Connectivity (20 pts)
    connectivity = result.get('connectivity_passed', False)
    http_get = result.get('http_get_code', '000')
    
    if connectivity:
        score += 20
        feedback_parts.append("Connectivity verified (GET 200 OK)")
    else:
        feedback_parts.append(f"Connectivity failed (GET code: {http_get})")

    # 4. Method Restriction (30 pts)
    security = result.get('security_test_passed', False)
    http_post = result.get('http_post_code', '000')
    
    if security:
        score += 30
        feedback_parts.append(f"Security restriction verified (POST blocked with {http_post})")
    else:
        # If connectivity failed, security test might be invalid (000), or if it passed (200), that's a fail.
        if http_post in ['200', '201', '204']:
            feedback_parts.append("Security FAIL: POST request was allowed (Critical vulnerability)")
        else:
            feedback_parts.append(f"Security test inconclusive (Code: {http_post})")

    # 5. Clean Logs (10 pts)
    logs_ok = result.get('monitor_logs_ok', False)
    if logs_ok:
        score += 10
        feedback_parts.append("Monitor logs show successful operation")
    else:
        feedback_parts.append("Monitor logs show errors or no activity")

    # Calculate Pass
    # Strict requirement: Must have separated the socket (Criterion 1 & 2) AND implemented blocking (Criterion 4)
    # Connectivity is important but maybe partial fail is ok? No, a broken proxy is useless.
    # Threshold 70 means they can miss Clean Logs (10) and maybe Connectivity (20) if they got everything else? 
    # No, if connectivity fails, the app is broken.
    
    passed = score >= 70 and connectivity and security

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }