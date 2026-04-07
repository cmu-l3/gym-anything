#!/usr/bin/env python3
"""Verifier for binary_dicom_transfer task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_binary_dicom_transfer(traj, env_info, task_info):
    """
    Verify that the DICOM file was transferred with binary integrity preserved.
    
    Criteria:
    1. Channel created and deployed (20 pts)
    2. Output file exists (20 pts)
    3. Filename matches pattern (10 pts)
    4. BINARY INTEGRITY (MD5 Match) (50 pts) - Critical
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dicom_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    channel_exists = result.get('channel_exists', False)
    channel_state = result.get('channel_state', 'UNKNOWN')
    output_exists = result.get('output_exists', False)
    filename_correct = result.get('filename_correct', False)
    md5_match = result.get('md5_match', False)
    file_created = result.get('file_created_during_task', False)
    
    score = 0
    feedback_parts = []
    
    # 1. Channel Status (20 pts)
    if channel_exists:
        score += 10
        feedback_parts.append("Channel 'DICOM_Migration' created")
        
        if channel_state in ['STARTED', 'DEPLOYED', 'RUNNING']:
            score += 10
            feedback_parts.append(f"Channel is {channel_state}")
        else:
            feedback_parts.append(f"Channel state is {channel_state} (expected STARTED)")
    else:
        feedback_parts.append("Channel 'DICOM_Migration' not found")

    # 2. Output File Existence (20 pts)
    if output_exists and file_created:
        score += 20
        feedback_parts.append("New output file found")
    elif output_exists:
        score += 5
        feedback_parts.append("Output file found but timestamp suggests it wasn't created during task")
    else:
        feedback_parts.append("No output file found in /home/ga/dicom_output/")

    # 3. Filename Pattern (10 pts)
    if filename_correct:
        score += 10
        feedback_parts.append("Filename has correct '_migrated' suffix")
    elif output_exists:
        feedback_parts.append(f"Filename '{result.get('output_filename')}' does not match pattern")

    # 4. Binary Integrity (50 pts) - CRITICAL
    if md5_match:
        score += 50
        feedback_parts.append("SUCCESS: Binary integrity preserved (MD5 match)")
    elif output_exists:
        feedback_parts.append("FAILURE: File corrupted! MD5 mismatch. Likely processed as Text instead of Binary.")
    
    # Pass logic
    passed = (score >= 90) # Requires almost perfect execution, definitely needs MD5 match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }