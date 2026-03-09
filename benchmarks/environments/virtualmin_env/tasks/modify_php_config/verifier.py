#!/usr/bin/env python3
"""
Verifier for modify_php_config task.

Verifies:
1. PHP configuration values match the requirements (via CLI check)
2. PHP runtime values match the requirements (via live web check)
3. Configuration files were actually modified during the task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_php_config(traj, env_info, task_info):
    """
    Verify that PHP configuration directives were updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {
        "upload_max_filesize": "64M",
        "post_max_size": "128M",
        "memory_limit": "256M",
        "max_execution_time": "300"
    })

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    max_score = 100
    feedback = []
    
    cli_values = result.get('cli_values', {})
    runtime_values = result.get('runtime_json', {})
    anti_gaming = result.get('anti_gaming', {})

    # Helper to normalize values for comparison (e.g., "64M" vs "64M ")
    def normalize(val):
        if not val:
            return ""
        return str(val).strip()

    # 1. Verify Configuration Values (20 points each = 80 total)
    for key, target_val in expected.items():
        cli_val = normalize(cli_values.get(key))
        runtime_val = normalize(runtime_values.get(key))
        
        # We accept success if EITHER the CLI or Runtime matches
        # Runtime is authoritative, but CLI is acceptable if runtime fails due to service restart lag
        match = False
        
        if cli_val == target_val:
            match = True
        elif runtime_val == target_val:
            match = True
        
        # Special case handling for PHP size units consistency (optional but good practice)
        # Assuming exact string match for this task based on description
        
        if match:
            score += 20
            feedback.append(f"✓ {key} set to {target_val}")
        else:
            feedback.append(f"✗ {key}: expected {target_val}, found CLI='{cli_val}', Runtime='{runtime_val}'")

    # 2. Verify Anti-Gaming / Process (20 points)
    # Did the user actually modify the file during the task?
    was_modified = anti_gaming.get('was_modified', False)
    
    if was_modified:
        score += 20
        feedback.append("✓ Configuration file modified during task")
    else:
        # If score is high (values are correct) but file wasn't modified, 
        # it implies they were already correct (should have been reset by setup)
        # or the agent used a method that didn't touch the standard file (unlikely in Virtualmin)
        if score > 0:
            feedback.append("⚠ Configuration file timestamp unchanged (Pre-existing state or unconventional edit)")
        else:
            feedback.append("✗ No changes detected")

    # Final Evaluation
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }