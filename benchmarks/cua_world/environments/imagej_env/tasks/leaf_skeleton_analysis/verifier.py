#!/usr/bin/env python3
"""
Verifier for Leaf Vein Network Skeleton Analysis.

Verification Strategy:
1. Check if result CSV exists and was created during the task.
2. Verify the CSV contains expected Skeleton Analysis columns.
3. Verify the data indicates a complex network (high branch/junction count) 
   rather than noise or a trivial object.
4. Optional VLM check on trajectory to confirm skeletonization visualization.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_leaf_skeleton_analysis(traj, env_info, task_info):
    """
    Verify the leaf skeleton analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    # Get metadata expectations
    metadata = task_info.get('metadata', {})
    expected_min_branches = metadata.get('expected_min_branches', 20)
    expected_min_junctions = metadata.get('expected_min_junctions', 5)

    try:
        # Load result JSON
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/leaf_skeleton_analysis_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        
        # 1. File existence and creation time (20 pts)
        file_exists = result.get('file_exists', False)
        created_during = result.get('file_created_during_task', False)
        
        if file_exists and created_during:
            score += 20
            feedback_parts.append("Result file created successfully")
        elif file_exists:
            feedback_parts.append("Result file exists but timestamp suggests pre-existence")
        else:
            feedback_parts.append("Result file not found")
            return {"passed": False, "score": 0, "feedback": "Result file not found"}

        # 2. Branch Count (30 pts)
        # Real vein network should have many branches
        max_branches = result.get('max_branches', 0)
        if max_branches >= expected_min_branches:
            score += 30
            feedback_parts.append(f"Vein network detected (Max branches: {max_branches})")
        elif max_branches > 0:
            score += 15
            feedback_parts.append(f"Weak network detected (Max branches: {max_branches}, expected > {expected_min_branches})")
        else:
            feedback_parts.append("No branches detected in data")

        # 3. Junction Count (30 pts)
        max_junctions = result.get('max_junctions', 0)
        if max_junctions >= expected_min_junctions:
            score += 30
            feedback_parts.append(f"Network complexity verified (Max junctions: {max_junctions})")
        elif max_junctions > 0:
            score += 15
            feedback_parts.append(f"Low complexity (Max junctions: {max_junctions})")
        else:
            feedback_parts.append("No junctions detected")

        # 4. Data Completeness (20 pts)
        has_avg_len = result.get('avg_branch_length_detected', False)
        has_endpoints = result.get('has_endpoints_data', False)
        
        if has_avg_len and has_endpoints:
            score += 20
            feedback_parts.append("Full skeleton metrics present")
        elif has_avg_len or has_endpoints:
            score += 10
            feedback_parts.append("Partial skeleton metrics present")
        else:
            feedback_parts.append("Missing standard skeleton analysis columns")

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}