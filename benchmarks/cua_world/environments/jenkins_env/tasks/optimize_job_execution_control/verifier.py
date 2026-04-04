#!/usr/bin/env python3
"""
Verifier for Optimize Job Execution Control task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_job_execution_control(traj, env_info, task_info):
    """
    Verify the Docs-Site-Gen job configuration.
    
    Expected:
    - Job exists
    - concurrentBuild is FALSE (Prevent concurrent builds)
    - quietPeriod is 60 (Wait 60 seconds)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_quiet = metadata.get('expected_quiet_period', 60)
    # Task asks to PREVENT concurrent builds, so concurrentBuild property should be False
    expected_concurrent = metadata.get('expected_concurrent_build', False)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/optimize_job_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
        
        score = 0
        feedback_parts = []
        
        # 1. Check Job Existence (20 pts)
        if result.get('job_exists'):
            score += 20
            feedback_parts.append("Job found")
        else:
            return {"passed": False, "score": 0, "feedback": "Job 'Docs-Site-Gen' was deleted or not found."}

        # 2. Check Concurrent Builds (40 pts)
        # We want concurrent_build to be False
        actual_concurrent = result.get('concurrent_build')
        if actual_concurrent is False:
            score += 40
            feedback_parts.append("Concurrency correctly disabled")
        else:
            feedback_parts.append(f"Concurrency NOT disabled (current: {actual_concurrent})")

        # 3. Check Quiet Period (40 pts)
        actual_quiet = result.get('quiet_period')
        
        # Handle cases where it might be returned as string or int
        try:
            actual_quiet = int(actual_quiet)
        except (ValueError, TypeError):
            actual_quiet = 0
            
        if actual_quiet == expected_quiet:
            score += 40
            feedback_parts.append(f"Quiet period correct ({actual_quiet}s)")
        else:
            feedback_parts.append(f"Quiet period incorrect (expected {expected_quiet}s, got {actual_quiet}s)")

        # Final Score
        passed = score == 100
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}