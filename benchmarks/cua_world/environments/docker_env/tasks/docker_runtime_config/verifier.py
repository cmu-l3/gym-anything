#!/usr/bin/env python3
"""
Verifier for docker_runtime_config task.

Criteria:
1. Image acme-dashboard:dynamic exists.
2. config.js receives API_URL injection.
3. nginx.conf receives WORKER_PROCESSES injection.
4. Nginx internal variables ($uri, $host) are NOT clobbered.
5. Nginx process is running (valid config).
6. Dockerfile installs gettext.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_runtime_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result file
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
    
    # 1. Image Exists (10 pts)
    if result.get("image_exists", False):
        score += 10
    else:
        feedback_parts.append("Image 'acme-dashboard:dynamic' not found")
        return {"passed": False, "score": 0, "feedback": "Image not found"}

    # 2. Config JS Injection (25 pts)
    if result.get("config_js_injected", False):
        score += 25
        feedback_parts.append("config.js injected successfully")
    else:
        feedback_parts.append("config.js did not contain injected API_URL")

    # 3. Nginx Conf Injection (25 pts)
    if result.get("nginx_conf_injected", False):
        score += 25
        feedback_parts.append("nginx.conf injected successfully")
    else:
        feedback_parts.append("nginx.conf did not contain injected WORKER_PROCESSES")

    # 4. Nginx Vars Preserved (20 pts)
    if result.get("nginx_vars_preserved", False):
        score += 20
        feedback_parts.append("Nginx internal variables preserved")
    else:
        feedback_parts.append("Nginx variables ($uri/$host) were clobbered (use envsubst '${VAR}...')")

    # 5. Nginx Running / Container Started (10 pts)
    if result.get("container_started", False) and result.get("nginx_running", False):
        score += 10
        feedback_parts.append("Container running healthy")
    else:
        feedback_parts.append("Container failed to start or Nginx crashed")

    # 6. Static Checks (10 pts)
    static_score = 0
    if result.get("dockerfile_has_gettext", False):
        static_score += 5
    if result.get("entrypoint_exists", False):
        static_score += 5
    
    if static_score == 10:
        feedback_parts.append("Dockerfile/Entrypoint structure correct")
    score += static_score

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }