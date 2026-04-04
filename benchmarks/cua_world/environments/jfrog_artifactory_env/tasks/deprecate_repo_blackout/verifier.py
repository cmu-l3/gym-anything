#!/usr/bin/env python3
"""
Verifier for deprecate_repo_blackout task.

Requirements:
1. Repository 'example-repo-local' must exist.
2. 'blackedOut' property must be true.
3. 'description' must contain "DEPRECATED: Migrated to new system".
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deprecate_repo_blackout(traj, env_info, task_info):
    """
    Verifies the repository deprecation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_desc = metadata.get('expected_description_prefix', "DEPRECATED: Migrated to new system")
    
    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Check Existence (20 pts)
    if result.get('repo_exists', False):
        score += 20
        feedback_parts.append("Repository 'example-repo-local' found")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Repository 'example-repo-local' not found or could not be queried."
        }

    # 2. Check Blacked Out State (50 pts)
    is_blacked_out = result.get('blacked_out', False)
    if is_blacked_out:
        score += 50
        feedback_parts.append("Repository is Blacked Out")
    else:
        feedback_parts.append("Repository is NOT Blacked Out")

    # 3. Check Description (30 pts)
    description = result.get('description', "") or ""
    if expected_desc in description:
        score += 30
        feedback_parts.append(f"Description updated correctly ('{description}')")
    else:
        feedback_parts.append(f"Description incorrect or missing (Found: '{description}', Expected to contain: '{expected_desc}')")

    # Pass Threshold
    # Must have both Blacked Out AND Description correct to pass (Score >= 80)
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }