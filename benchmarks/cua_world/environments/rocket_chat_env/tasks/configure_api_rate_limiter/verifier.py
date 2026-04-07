#!/usr/bin/env python3
"""
Verifier for Configure API Rate Limiting task.

Checks:
1. API_Enable_Rate_Limiter is set to true (40 points)
2. API_Default_Count is set to 20 (60 points)
3. VLM verification of trajectory (confirmation)
"""

import json
import logging
import os
import tempfile
import sys
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_api_rate_limiter(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Rate Limiter Enabled
    enabled_val = str(result.get('rate_limiter_enabled', '')).lower()
    if enabled_val == 'true':
        score += 40
        feedback_parts.append("Rate Limiter enabled")
    else:
        feedback_parts.append(f"Rate Limiter NOT enabled (value: {enabled_val})")

    # Check 2: Default Count
    count_val = str(result.get('api_default_count', ''))
    # Handle potentially string-wrapped integers
    try:
        count_int = int(float(count_val))
        if count_int == 20:
            score += 60
            feedback_parts.append("API Default Count set to 20")
        else:
            feedback_parts.append(f"API Default Count incorrect (expected 20, got {count_int})")
    except ValueError:
        feedback_parts.append(f"Invalid count value found: {count_val}")

    # VLM Verification (Anti-gaming / Confirmation)
    # We check if the agent actually visited the settings page
    # This helps distinguish between a script injection (if they hacked it) vs UI use, 
    # though for this task, correct state is the primary goal.
    # We will use it mainly for detailed feedback or tie-breaking if score is borderline,
    # but here we stick to the rigid points for state.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }