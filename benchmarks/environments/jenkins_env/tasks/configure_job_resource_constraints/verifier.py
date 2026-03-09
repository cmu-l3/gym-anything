#!/usr/bin/env python3
"""
Verifier for Configure Job Resource Constraints task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_job_resource_constraints(traj, env_info, task_info):
    """
    Verify the job configuration changes.
    
    Requirements:
    1. concurrentBuild should be 'false'
    2. quietPeriod should be '45'
    3. assignedNode should be 'build-server-v2'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_job_name = metadata.get('job_name', 'Legacy-Monolith-Build')
    
    try:
        # Read result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Check 1: Job Exists (10 pts)
        if result.get('job_exists', False):
            score += 10
            feedback_parts.append(f"Job '{expected_job_name}' exists")
        else:
            return {"passed": False, "score": 0, "feedback": "Job not found"}

        # Check 2: Concurrent Builds Disabled (30 pts)
        # XML value comes as string "false" or "true"
        concurrent_val = str(result.get('concurrent_build', '')).lower().strip()
        if concurrent_val == 'false':
            score += 30
            feedback_parts.append("Concurrent builds disabled")
        else:
            feedback_parts.append(f"Concurrent builds not disabled (value: {concurrent_val})")

        # Check 3: Quiet Period (30 pts)
        quiet_val = str(result.get('quiet_period', '')).strip()
        if quiet_val == '45':
            score += 30
            feedback_parts.append("Quiet period set to 45s")
        else:
            feedback_parts.append(f"Quiet period incorrect (found: '{quiet_val}', expected: '45')")

        # Check 4: Node Restriction (30 pts)
        node_val = str(result.get('assigned_node', '')).strip()
        if node_val == 'build-server-v2':
            score += 30
            feedback_parts.append("Node label set to 'build-server-v2'")
        elif 'build-server-v2' in node_val:
            # Partial credit if they messed up the expression syntax but got the label right
            score += 15
            feedback_parts.append(f"Node label close but not exact ('{node_val}')")
        else:
            feedback_parts.append(f"Node label incorrect (found: '{node_val}')")

        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}