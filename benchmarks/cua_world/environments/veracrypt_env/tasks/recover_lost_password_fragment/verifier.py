#!/usr/bin/env python3
"""
Verifier for recover_lost_password_fragment task.

Scoring Criteria:
1. Volume is successfully mounted (60 pts)
   - Must be mounted at the specific path requested (/home/ga/MountPoints/recovered)
2. Recovered ID is correct (40 pts)
   - The file /home/ga/Documents/recovered_id.txt must contain the correct 3-digit number.
   - Must match the randomized ground truth generated during setup.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recover_lost_password(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
            
        is_mounted = result.get('is_volume_mounted', False)
        actual_mp = result.get('actual_mount_point', '')
        expected_mp = result.get('expected_mount_point', '')
        manifest_accessible = result.get('manifest_accessible', False)
        
        ground_truth_id = str(result.get('ground_truth_id', ''))
        file_content = str(result.get('output_file_content', ''))
        file_exists = result.get('output_file_exists', False)
        file_fresh = result.get('file_created_during_task', False)

        # 1. Verify Mount Status (60 pts)
        mount_score = 0
        if is_mounted:
            if actual_mp == expected_mp:
                mount_score = 60
                feedback_parts.append(f"Volume correctly mounted at {actual_mp}")
            else:
                mount_score = 30 # Partial credit for mounting at wrong location
                feedback_parts.append(f"Volume mounted, but at wrong location ({actual_mp} vs {expected_mp})")
            
            # Additional check for data integrity
            if not manifest_accessible:
                mount_score -= 10
                feedback_parts.append("Warning: Volume mounted but data not accessible")
        else:
            feedback_parts.append("Volume NOT mounted")
        
        score += mount_score

        # 2. Verify Recovered ID (40 pts)
        id_score = 0
        if file_exists:
            # Flexible matching: check if ground truth is in content or exact match
            if ground_truth_id == file_content:
                id_score = 40
                feedback_parts.append(f"Correct ID recovered: {ground_truth_id}")
            elif ground_truth_id in file_content:
                # If they wrote "ID: 472" instead of just "472"
                id_score = 40
                feedback_parts.append(f"Correct ID found in output: {ground_truth_id}")
            else:
                feedback_parts.append(f"Incorrect ID. Expected: {ground_truth_id}, Found: {file_content}")
            
            # Anti-gaming penalty
            if not file_fresh:
                id_score = 0
                feedback_parts.append("Output file timestamp indicates it was not created during this task")
        else:
            feedback_parts.append("Output file recovered_id.txt not found")
        
        score += id_score

    except Exception as e:
        logger.error(f"Verification Logic Error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification logic error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }