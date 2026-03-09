#!/usr/bin/env python3
"""
Verifier for optimize_virtual_repo_order task.
Checks if the virtual repository 'team-virtual' has 'team-local' prioritized over 'team-remote'.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_virtual_repo_order(traj, env_info, task_info):
    """
    Verify that team-virtual is configured with team-local first in the resolution order.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_repo = metadata.get('target_repo', 'team-virtual')
    expected_first = metadata.get('expected_first', 'team-local')
    expected_second = metadata.get('expected_second', 'team-remote')

    # Copy result JSON from container
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

    # Extract configuration
    config = result.get('config', {})
    
    # Check 1: Repository exists
    if not config.get('exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Repository 'team-virtual' could not be retrieved via API. It may have been deleted."
        }

    # Check 2: Correct Key and Type
    if config.get('key') != target_repo:
        return {"passed": False, "score": 0, "feedback": f"Retrieved config for wrong repo: {config.get('key')}"}
        
    if config.get('type') != 'virtual':
        return {"passed": False, "score": 0, "feedback": "Repository is not a Virtual repository."}

    # Check 3: Resolution Order
    repos = config.get('repositories', [])
    
    score = 0
    feedback_parts = []
    
    # Verify membership
    if expected_first in repos:
        score += 10
    else:
        feedback_parts.append(f"MISSING: {expected_first}")
        
    if expected_second in repos:
        score += 10
    else:
        feedback_parts.append(f"MISSING: {expected_second}")

    # Verify Order (Primary Goal)
    # Ideally: [team-local, team-remote, ...]
    
    if len(repos) < 2:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Repository list too short to verify order: {repos}"
        }

    actual_first = repos[0]
    actual_second = repos[1]

    order_correct = False
    
    if actual_first == expected_first:
        score += 50
        feedback_parts.append(f"SUCCESS: {expected_first} is prioritized (1st).")
        order_correct = True
    else:
        feedback_parts.append(f"FAIL: {actual_first} is 1st (expected {expected_first}).")

    if actual_second == expected_second:
        score += 30
        feedback_parts.append(f"SUCCESS: {expected_second} is 2nd.")
    else:
        feedback_parts.append(f"FAIL: {actual_second} is 2nd (expected {expected_second}).")

    # Final Evaluation
    passed = order_correct and (expected_second in repos)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }