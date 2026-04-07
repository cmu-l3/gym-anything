#!/usr/bin/env python3
"""
Verifier for fix_cloud_backup_rotator task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_cloud_backup_rotator(traj, env_info, task_info):
    """
    Verify that the S3 backup rotator script has been fixed.
    
    Scoring:
    - 35 pts: Retention logic fixed (test_retention_keeps_newest)
    - 35 pts: Pagination logic fixed (test_large_bucket_pagination)
    - 30 pts: Glacier protection added (test_skips_glacier)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Retrieve result file
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
            
    score = 0
    feedback_parts = []
    
    # 1. Retention Logic (35 pts)
    if result.get('retention_passed', False):
        score += 35
        feedback_parts.append("Retention logic fixed (files correctly kept/deleted)")
    else:
        feedback_parts.append("Retention logic NOT fixed (test_retention_keeps_newest failed)")
        
    # 2. Pagination Logic (35 pts)
    if result.get('pagination_passed', False):
        score += 35
        feedback_parts.append("Pagination logic fixed (large buckets processed correctly)")
    else:
        # Check if it was infinite loop (timeout)
        if result.get('pytest_exit_code') == 124: # Timeout exit code
            feedback_parts.append("Pagination logic caused infinite loop/timeout")
        else:
            feedback_parts.append("Pagination logic NOT fixed (test_large_bucket_pagination failed)")

    # 3. Glacier Protection (30 pts)
    if result.get('glacier_passed', False):
        score += 30
        feedback_parts.append("Glacier protection added")
    else:
        feedback_parts.append("Glacier protection NOT fixed (test_skips_glacier failed)")
        
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }