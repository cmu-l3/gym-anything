#!/usr/bin/env python3
"""
Verifier for Deprecate Jenkins Job task.
Checks:
1. Job still exists (was not deleted).
2. Job is disabled.
3. Job description contains specific deprecation text.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deprecate_jenkins_job(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_desc_fragment = metadata.get('expected_description_fragment', "DEPRECATED: Migrated to microservices pipeline")

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/deprecate_job_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        
        job_exists = result.get('job_exists', False)
        is_disabled = result.get('is_disabled', False)
        description = result.get('description', '') or ''
        
        # Criterion 1: Job Exists (10 pts)
        if job_exists:
            score += 10
            feedback_parts.append("Job exists")
        else:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Job was deleted or not found. Instructions were to disable, not delete."
            }
            
        # Criterion 2: Job Disabled (50 pts)
        if is_disabled:
            score += 50
            feedback_parts.append("Job successfully disabled")
        else:
            feedback_parts.append("Job is still enabled (buildable)")
            
        # Criterion 3: Description Updated (40 pts)
        # Normalize strings for robust comparison
        if expected_desc_fragment.lower() in description.lower():
            score += 40
            feedback_parts.append("Description updated correctly")
        else:
            feedback_parts.append(f"Description missing required text: '{expected_desc_fragment}'")
            
        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}