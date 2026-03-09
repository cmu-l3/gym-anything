#!/usr/bin/env python3
"""
Verifier for switch_php_fpm task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_switch_php_fpm(traj, env_info, task_info):
    """
    Verify that the PHP execution mode was changed to FPM and max_children set to 5.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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
    
    # Criterion 1: PHP Mode is FPM (Virtualmin Config) - 35 pts
    if result.get('is_fpm_configured', False):
        score += 35
        feedback_parts.append("PHP mode set to FPM")
    else:
        feedback_parts.append("PHP mode NOT set to FPM")

    # Criterion 2: Pool Config Exists - 10 pts
    if result.get('pool_file_exists', False):
        score += 10
        feedback_parts.append("FPM pool config found")
    else:
        feedback_parts.append("FPM pool config missing")

    # Criterion 3: max_children set to 5 - 20 pts
    # Value is string in JSON, strip whitespace
    max_children = str(result.get('max_children_value', '0')).strip()
    if max_children == '5':
        score += 20
        feedback_parts.append("pm.max_children correct (5)")
    else:
        feedback_parts.append(f"pm.max_children incorrect ({max_children})")

    # Criterion 4: Service Running - 10 pts
    if result.get('service_active', False):
        score += 10
        feedback_parts.append("PHP-FPM service active")
    else:
        feedback_parts.append("PHP-FPM service inactive")

    # Criterion 5: Functional Test (Server API) - 15 pts
    api_response = result.get('php_api_response', 'unknown')
    if "FPM" in api_response or "FastCGI" in api_response:
        score += 15
        feedback_parts.append(f"PHP executing via {api_response}")
    else:
        feedback_parts.append(f"PHP execution verification failed (API: {api_response})")

    # Criterion 6: Task Integrity (Implicit) - 10 pts
    # If mode is FPM and config exists, we assume work was done during task
    # (since we reset to CGI in setup)
    if result.get('is_fpm_configured', False) and result.get('pool_file_exists', False):
        score += 10

    passed = score >= 55 and result.get('is_fpm_configured', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }