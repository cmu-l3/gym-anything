#!/usr/bin/env python3
"""
Verifier for Retry Failed Deployment task.

Checks if the agent triggered a new build with:
1. ARTIFACT_TAG matching Build #3 (exact match required)
2. REGION matching Build #3
3. FORCE_RESTART set to true (was false in Build #3)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retry_failed_deployment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract values
    last_build_number = result.get('last_build_number', 0)
    actual_tag = result.get('actual_tag', '')
    actual_region = result.get('actual_region', '')
    actual_restart = result.get('actual_restart', False)
    
    expected_tag = result.get('expected_tag', '')
    expected_region = result.get('expected_region', '')

    feedback_parts = []
    score = 0

    # Criterion 1: New Build Triggered (20 pts)
    # Setup creates 3 builds, so a new one must be > 3
    if last_build_number > 3:
        score += 20
        feedback_parts.append(f"New build triggered (Build #{last_build_number})")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new build triggered. Last build is still #" + str(last_build_number)
        }

    # Criterion 2: Correct Artifact Tag (35 pts)
    if actual_tag == expected_tag:
        score += 35
        feedback_parts.append("Artifact Tag matches Build #3")
    else:
        feedback_parts.append(f"Wrong Tag: Expected '{expected_tag}', got '{actual_tag}'")

    # Criterion 3: Correct Region (15 pts)
    if actual_region == expected_region:
        score += 15
        feedback_parts.append("Region matches Build #3")
    else:
        feedback_parts.append(f"Wrong Region: Expected '{expected_region}', got '{actual_region}'")

    # Criterion 4: Force Restart Enabled (30 pts)
    # This MUST be true (it was false in the failed build)
    if actual_restart is True:
        score += 30
        feedback_parts.append("Force Restart enabled")
    else:
        feedback_parts.append("Force Restart was NOT enabled")

    # Final Verification
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }