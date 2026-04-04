#!/usr/bin/env python3
"""
Verifier for fix_broken_server_config task.
Checks service status, configuration validity, and verification file.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_server_config(traj, env_info, task_info):
    """
    Verify the agent fixed the server configuration and verified the fix.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criterion 1: Service Status (30 pts)
    service_active = result.get('service_active') == 'active'
    http_status = result.get('http_status')
    
    if service_active and http_status in ['200', '302']:
        score += 30
        feedback_parts.append("Service is active and responding (HTTP 200/302).")
    elif service_active:
        score += 15
        feedback_parts.append(f"Service is active but HTTP status is {http_status} (expected 200/302).")
    else:
        feedback_parts.append("Service is NOT active.")

    # Criterion 2: Valid Key Configuration (35 pts total)
    if result.get('key_changed', False):
        score += 10
        feedback_parts.append("Configuration file was modified.")
        
        if result.get('valid_fernet', False):
            score += 25
            feedback_parts.append("New encryption key is valid.")
        else:
            feedback_parts.append("New encryption key is INVALID (must be a valid Fernet key).")
    else:
        feedback_parts.append("Configuration file still contains the broken key.")

    # Criterion 3: Database/App Functionality (10 pts)
    if result.get('db_working', False):
        score += 10
        feedback_parts.append("Database connection is working.")
    else:
        feedback_parts.append("Database connection failed (app might still be broken).")

    # Criterion 4: Verification File (Anti-Gaming) (25 pts total)
    if result.get('verification_file_exists', False):
        score += 5
        feedback_parts.append("Verification file exists.")
        
        if result.get('count_correct', False):
            score += 10
            feedback_parts.append("Aircraft count in file is correct.")
        else:
            feedback_parts.append(f"Aircraft count incorrect (Expected: {result.get('expected_count')}, Got: {result.get('verification_file_content')}).")

        if result.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("File was created during the task window.")
        else:
            feedback_parts.append("File timestamp is too old (pre-dated task start).")
    else:
        feedback_parts.append("Verification file (/home/ga/repair_verification.txt) not found.")

    # Pass/Fail Logic
    # Must have working service, valid key, and working DB to pass
    core_requirements = (
        service_active and 
        result.get('valid_fernet', False) and 
        result.get('db_working', False)
    )
    
    passed = core_requirements and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }