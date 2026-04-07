#!/usr/bin/env python3
"""
Verifier for migrate_apache_to_nginx task.

This evaluates the infrastructure migration securely using the exported JSON state.
CRITERIA:
1. System services migrated (Apache off, Nginx/PHP-FPM on) (20 points)
2. HTTP server header reflects Nginx and PHP executes successfully (20 points)
3. Framework routing functions correctly (/login returns 200 OK) (30 points)
4. Security headers (X-Frame-Options and X-Content-Type-Options) match expectations (30 points)
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_apache_to_nginx(traj, env_info, task_info):
    # Enforce safe retrieval of artifacts using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Execution error: copy_from_env not available in env_info"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Evaluate Service States
    apache_state = result.get("apache2_state", "")
    nginx_state = result.get("nginx_state", "")
    phpfpm_state = result.get("phpfpm_state", "")

    if apache_state != "active" and nginx_state == "active" and phpfpm_state == "active":
        score += 20
        feedback.append("Service Check Passed: Apache2 is inactive, Nginx and PHP-FPM are active.")
    else:
        feedback.append(f"Service Check Failed: (Apache:{apache_state}, Nginx:{nginx_state}, PHP:{phpfpm_state}).")

    # 2. Evaluate Base Configurations
    root_status = result.get("root_status", "")
    server_header = result.get("server_header", "").lower()
    php_executed = result.get("php_executed", False)

    # 200, 301, or 302 are acceptable at the root depending on authentication state redirects
    if root_status in ["200", "301", "302"] and "nginx" in server_header and php_executed:
        score += 20
        feedback.append("Base Config Passed: Nginx is successfully serving the executing PHP application.")
    else:
        feedback.append(f"Base Config Failed: (HTTP Status: {root_status}, Server Header: {server_header}, PHP Executed: {php_executed}).")

    # 3. Evaluate Framework Routing (Try-files directive implementation)
    login_status = result.get("login_status", "")
    
    if login_status == "200":
        score += 30
        feedback.append("Framework Routing Passed: Sub-page /login resolves natively.")
    else:
        feedback.append(f"Framework Routing Failed: /login returned {login_status}. Your Nginx 'try_files' directive might be missing or incorrect.")

    # 4. Evaluate Security Headers
    x_frame = result.get("x_frame_options", "").lower()
    x_content = result.get("x_content_type_options", "").lower()

    if x_frame == "sameorigin":
        score += 15
        feedback.append("Security Header Passed: X-Frame-Options is SAMEORIGIN.")
    else:
        feedback.append(f"Security Header Failed: X-Frame-Options was '{x_frame}' (Expected 'sameorigin').")

    if x_content == "nosniff":
        score += 15
        feedback.append("Security Header Passed: X-Content-Type-Options is nosniff.")
    else:
        feedback.append(f"Security Header Failed: X-Content-Type-Options was '{x_content}' (Expected 'nosniff').")

    # Crucial minimum requirements: Must have routed NGINX to pass the task fundamentally
    passed = (score >= 70) and (login_status == "200") and ("nginx" in server_header) and (apache_state != "active")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }