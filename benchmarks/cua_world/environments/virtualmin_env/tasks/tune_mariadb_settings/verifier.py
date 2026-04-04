#!/usr/bin/env python3
"""
Verifier for tune_mariadb_settings task.

Verifies:
1. MariaDB service is running (10 pts)
2. max_connections is 250 (30 pts)
3. wait_timeout is 300 (30 pts)
4. innodb_buffer_pool_size is ~256MB (30 pts)

CRITICAL: Checks runtime values. If agent edited config but didn't restart,
runtime values will be unchanged and task will fail (as intended).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tune_mariadb_settings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_max = int(metadata.get('expected_max_connections', 250))
    expected_timeout = int(metadata.get('expected_wait_timeout', 300))
    expected_buffer = int(metadata.get('expected_buffer_pool_bytes', 268435456))
    tolerance = int(metadata.get('buffer_pool_tolerance_bytes', 1048576)) # 1MB tolerance

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Service Status (10 pts)
    if result.get('service_active', False):
        score += 10
        feedback.append("MariaDB service is running")
    else:
        feedback.append("MariaDB service is NOT running (CRITICAL FAIL)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    runtime = result.get('runtime_values', {})
    
    # 2. Check max_connections (30 pts)
    try:
        actual_max = int(runtime.get('max_connections', 0))
        if actual_max == expected_max:
            score += 30
            feedback.append(f"max_connections correctly set to {actual_max}")
        else:
            feedback.append(f"max_connections is {actual_max} (expected {expected_max})")
    except ValueError:
        feedback.append("Could not parse max_connections value")

    # 3. Check wait_timeout (30 pts)
    try:
        actual_timeout = int(runtime.get('wait_timeout', 0))
        if actual_timeout == expected_timeout:
            score += 30
            feedback.append(f"wait_timeout correctly set to {actual_timeout}")
        else:
            # Check if they set interactive_timeout instead or mixed them up
            feedback.append(f"wait_timeout is {actual_timeout} (expected {expected_timeout})")
    except ValueError:
        feedback.append("Could not parse wait_timeout value")

    # 4. Check innodb_buffer_pool_size (30 pts)
    try:
        actual_buffer = int(runtime.get('innodb_buffer_pool_size', 0))
        diff = abs(actual_buffer - expected_buffer)
        
        if diff <= tolerance:
            score += 30
            feedback.append(f"innodb_buffer_pool_size correctly set to ~256MB ({actual_buffer} bytes)")
        else:
            # Check for common mistake: Did they edit file but not restart?
            config_evidence = result.get('config_file_evidence', {}).get('buffer_pool_found', 0)
            if config_evidence > 0 and diff > tolerance:
                feedback.append(f"Buffer pool incorrect ({actual_buffer} bytes). Config file was edited but server likely NOT restarted.")
            else:
                feedback.append(f"innodb_buffer_pool_size is {actual_buffer} bytes (expected ~{expected_buffer})")
    except ValueError:
        feedback.append("Could not parse innodb_buffer_pool_size value")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }