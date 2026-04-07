#!/usr/bin/env python3
"""
Verifier for enforce_strong_password_policy task.
Checks if the OpenProject system settings match the required security policy.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_strong_password_policy(traj, env_info, task_info):
    """
    Verify that the password policy was updated correctly.
    
    Criteria:
    1. password_min_length == 12 (50 points)
    2. password_active_rules contains 'uppercase' (15 points)
    3. password_active_rules contains 'lowercase' (15 points)
    4. password_active_rules contains 'numeric' (20 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Check for extraction errors
    if result.get("error"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification failed: Unable to retrieve settings ({result.get('error')})"
        }

    # Get values
    actual_length = result.get("min_length", 0)
    actual_rules = result.get("active_rules", [])
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_length = metadata.get('expected_min_length', 12)
    # Ensure active_rules is a list of strings
    if not isinstance(actual_rules, list):
        actual_rules = []
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Length (50 pts)
    if actual_length == expected_length:
        score += 50
        feedback_parts.append(f"Min length correct ({actual_length})")
    else:
        feedback_parts.append(f"Min length incorrect (expected {expected_length}, got {actual_length})")
        
    # Criterion 2: Uppercase (15 pts)
    if "uppercase" in actual_rules:
        score += 15
        feedback_parts.append("Uppercase required")
    else:
        feedback_parts.append("Uppercase NOT required")
        
    # Criterion 3: Lowercase (15 pts)
    if "lowercase" in actual_rules:
        score += 15
        feedback_parts.append("Lowercase required")
    else:
        feedback_parts.append("Lowercase NOT required")

    # Criterion 4: Numeric (20 pts)
    if "numeric" in actual_rules:
        score += 20
        feedback_parts.append("Numeric required")
    else:
        feedback_parts.append("Numeric NOT required")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }