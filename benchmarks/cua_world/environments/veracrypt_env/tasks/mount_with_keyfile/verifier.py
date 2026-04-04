#!/usr/bin/env python3
"""Verifier for mount_with_keyfile task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mount_with_keyfile(traj, env_info, task_info):
    """
    Verify that the user mounted the volume with password+keyfile and listed contents.
    
    Scoring:
    - Volume Mounted (30 pts): secure_finance.hc appears in VeraCrypt list
    - Correct Mount Point (20 pts): Mounted at /home/ga/MountPoints/slot1
    - Files Accessible (25 pts): Expected files found at mount point
    - Contents Documented (25 pts): Output file exists, is new, and contains filenames
    
    Pass Threshold: 65 points (Must at least mount volume and access files)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_files = metadata.get('expected_files', [])
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Read result file
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: Volume Mounted (30 pts)
        if result.get('volume_is_mounted', False):
            score += 30
            feedback_parts.append("Volume secure_finance.hc is mounted")
        else:
            feedback_parts.append("Volume is NOT mounted")

        # Criterion 2: Correct Mount Point (20 pts)
        # Check if target mount point is active AND (optional but good) matches list
        target_active = result.get('target_mount_point_active', False)
        list_path = result.get('mount_path_from_list', '')
        
        # We give points if the target directory is a mountpoint. 
        # If Veracrypt list confirms it, that's ideal.
        if target_active:
            score += 20
            feedback_parts.append("Target directory is a mount point")
        elif '/home/ga/MountPoints/slot1' in list_path:
            # Maybe mountpoint check failed due to permissions but list shows it
            score += 20
            feedback_parts.append("VeraCrypt reports correct mount path")
        else:
            feedback_parts.append("Volume not mounted at requested /home/ga/MountPoints/slot1")

        # Criterion 3: Files Accessible (25 pts)
        if result.get('files_accessible', False):
            score += 25
            feedback_parts.append("Files inside volume are accessible")
        else:
            feedback_parts.append("Files inside volume could not be accessed")

        # Criterion 4: Contents Documented (25 pts)
        output_exists = result.get('output_file_exists', False)
        output_new = result.get('output_created_during_task', False)
        content = result.get('output_content', '')
        
        if output_exists and output_new:
            # Check content accuracy
            matches = 0
            for filename in expected_files:
                if filename in content:
                    matches += 1
            
            if matches >= 2:
                score += 25
                feedback_parts.append("Contents list file created with correct filenames")
            elif matches > 0:
                score += 15
                feedback_parts.append("Contents list file created but incomplete")
            else:
                score += 10
                feedback_parts.append("Contents list file created but empty/incorrect")
        elif output_exists:
            # Existed before? Suspicious or partial
            score += 5
            feedback_parts.append("Contents file exists but timestamp is old")
        else:
            feedback_parts.append("Contents list file not created")

    except Exception as e:
        logger.error(f"Verification exception: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Pass threshold
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }