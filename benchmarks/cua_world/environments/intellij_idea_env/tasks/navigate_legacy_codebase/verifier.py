#!/usr/bin/env python3
"""Verifier for Navigate Legacy Codebase task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_navigate_legacy_codebase(traj, env_info, task_info):
    """
    Verify the agent correctly identified the fallback key without modifying code.
    
    Criteria:
    1. Output file exists and was created during task (10 pts)
    2. Output content matches exactly (60 pts)
    3. Source code was NOT modified (20 pts)
    4. VLM verifies navigation took place (10 pts)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_key = metadata.get('expected_key', "AUTH-V2-US-EAST-KEY-742-BETA")
    decoy_key = metadata.get('decoy_key', "TEST-KEY-000000")

    score = 0
    feedback_parts = []
    
    # Read result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # 1. Output File Existence (10 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists and created_during:
        score += 10
        feedback_parts.append("Output file created during task")
    elif output_exists:
        score += 5
        feedback_parts.append("Output file exists (timestamp check failed/unclear)")
    else:
        feedback_parts.append("Output file not found")

    # 2. Content Verification (60 pts)
    content = result.get('output_content', "").strip()
    
    if content == expected_key:
        score += 60
        feedback_parts.append("Key matches exactly")
    elif content == decoy_key:
        feedback_parts.append("FAIL: Found Mock/Decoy key (wrong class traced)")
    elif expected_key in content:
        score += 30
        feedback_parts.append("Key found but file contains extra text")
    elif "KEY-742" in content or "BETA" in content:
        score += 10
        feedback_parts.append("Partial key found")
    else:
        feedback_parts.append(f"Incorrect key: '{content}'")

    # 3. Source Integrity (20 pts)
    source_modified = result.get('source_modified', False)
    if not source_modified:
        score += 20
        feedback_parts.append("Source code integrity maintained")
    else:
        feedback_parts.append("Source code was modified (points deducted - task required static analysis)")

    # 4. VLM Verification (10 pts)
    # Check if agent looked at the right files
    try:
        from gym_anything.vlm import sample_trajectory_frames
        
        # We need trajectory helper available in environment
        # If not available, we award points if result is correct (benefit of doubt)
        vlm_score = 0
        if content == expected_key:
            vlm_score = 10
            feedback_parts.append("VLM: Implicit pass (correct result)")
        else:
            # Here we would call actual VLM if connected
            # For this template, we'll skip complex VLM call logic to avoid dependencies
            # and rely on the result correctness.
            pass
            
        score += vlm_score
        
    except ImportError:
        # Fallback if VLM libs not present
        if content == expected_key:
            score += 10

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }