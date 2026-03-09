#!/usr/bin/env python3
"""
Verifier for configure_pr_auto_completion task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_pr_auto_completion(traj, env_info, task_info):
    """
    Verify that PR #1 was configured for auto-completion with Squash and Delete Source Branch.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temporary file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Using Windows path format for the source, expecting copy_from_env to handle it or mapping
        # The Azure DevOps environment maps C:\Users\Docker to /c/Users/Docker or similar usually, 
        # but copy_from_env typically takes the path as seen inside the guest OS.
        # Since the environment is Windows, we use the Windows path.
        copy_from_env("C:\\Users\\Docker\\task_results\\result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for API errors
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"API Error during verification: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Auto-Complete Enabled (40 points)
    if result.get('auto_complete_set', False):
        score += 40
        feedback_parts.append("Auto-complete enabled successfully")
    else:
        feedback_parts.append("Auto-complete was NOT enabled")
        # Critical failure, but we check other configs if they exist (unlikely if AC not set)
    
    # 2. Merge Strategy (30 points)
    strategy = result.get('merge_strategy', 'unknown')
    if strategy == 'squash':
        score += 30
        feedback_parts.append("Merge strategy is Squash")
    else:
        feedback_parts.append(f"Incorrect merge strategy: {strategy} (expected squash)")

    # 3. Delete Source Branch (30 points)
    delete_source = result.get('delete_source_branch', False)
    if delete_source:
        score += 30
        feedback_parts.append("Delete source branch option enabled")
    else:
        feedback_parts.append("Delete source branch option NOT enabled")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }