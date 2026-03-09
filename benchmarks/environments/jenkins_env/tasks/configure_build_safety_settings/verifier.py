#!/usr/bin/env python3
"""
Verifier for Configure Build Safety Settings task.

Requirements:
1. Production-Deploy job exists.
2. Concurrent builds are DISABLED (concurrentBuild == false).
3. Quiet period is set to 120 seconds.
4. Block build when upstream is building is ENABLED.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_build_safety_settings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_quiet = metadata.get('expected_quiet_period', 120)
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        # Initialize scoring
        score = 0
        max_score = 100
        feedback_parts = []
        
        job_found = result.get('job_found', False)
        config = result.get('config', {})
        
        # Criterion 0: Job Exists (Pre-requisite)
        if not job_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Job 'Production-Deploy' not found. It may have been deleted."
            }
        
        # Criterion 1: Disable Concurrent Builds (35 points)
        # We want concurrent_build to be FALSE
        is_concurrent = config.get('concurrent_build', True) # Default to True (bad) if missing
        if is_concurrent is False:
            score += 35
            feedback_parts.append("Concurrent builds disabled (Correct)")
        else:
            feedback_parts.append("Concurrent builds allowed (Incorrect - must be disabled)")

        # Criterion 2: Quiet Period (35 points)
        # Must be exactly 120
        actual_quiet = config.get('quiet_period', 0)
        if actual_quiet == expected_quiet:
            score += 35
            feedback_parts.append(f"Quiet period set to {actual_quiet}s (Correct)")
        else:
            feedback_parts.append(f"Quiet period is {actual_quiet}s (Incorrect - expected {expected_quiet}s)")

        # Criterion 3: Block on Upstream (30 points)
        # Must be TRUE
        block_upstream = config.get('block_upstream', False)
        if block_upstream is True:
            score += 30
            feedback_parts.append("Block when upstream building enabled (Correct)")
        else:
            feedback_parts.append("Block when upstream building disabled (Incorrect - must be enabled)")

        # Pass logic
        # All safety settings are critical
        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": config
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}