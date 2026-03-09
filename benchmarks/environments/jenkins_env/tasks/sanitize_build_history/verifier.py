#!/usr/bin/env python3
"""
Verifier for Sanitize Build History task.

Goal: Verify that builds #2 and #4 are deleted, while #1, #3, #5, #6 remain.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sanitize_build_history(traj, env_info, task_info):
    """
    Verify deletion of specific build records.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected config
    metadata = task_info.get('metadata', {})
    expected_deleted = set(metadata.get('builds_to_delete', [2, 4]))
    expected_kept = set(metadata.get('builds_to_keep', [1, 3, 5, 6]))
    
    try:
        # Load result
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
        
        job_exists = result.get('job_exists', False)
        remaining_builds = set(result.get('remaining_builds', []))
        
        feedback_parts = []
        score = 0
        
        # Criterion 1: Job must still exist (20 pts)
        if job_exists:
            score += 20
            feedback_parts.append("Job exists")
        else:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAILED: Job 'payment-gateway-ci' was deleted entirely. You were supposed to delete only specific builds."
            }
            
        # Criterion 2: Compromised builds deleted (25 pts each = 50 pts)
        deleted_correctly = True
        for b_id in expected_deleted:
            if b_id not in remaining_builds:
                score += 25
                feedback_parts.append(f"Build #{b_id} deleted")
            else:
                deleted_correctly = False
                feedback_parts.append(f"Build #{b_id} NOT deleted")
                
        # Criterion 3: Valid builds preserved (7.5 pts each = 30 pts)
        kept_correctly = True
        for b_id in expected_kept:
            if b_id in remaining_builds:
                score += 7.5
                feedback_parts.append(f"Build #{b_id} preserved")
            else:
                kept_correctly = False
                feedback_parts.append(f"Build #{b_id} accidentally deleted")
        
        # Check if score calculation results in float, round it
        score = int(score)
        
        # Determine pass/fail
        # Must strictly match the target state
        passed = (score >= 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}