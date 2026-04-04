#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tag_first_failure_build(traj, env_info, task_info):
    """
    Verify that the agent tagged the first failed build correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    target_id = data.get('target_build_id')
    target_desc = data.get('target_description', '') or ''
    prev_desc = data.get('prev_description', '') or ''
    next_desc = data.get('next_description', '') or ''
    
    # Metadata
    expected_tag = "Regression Start"
    
    # CRITERION 1: Target build is tagged correctly (60 pts)
    if expected_tag.lower() in target_desc.lower():
        score += 60
        feedback.append(f"SUCCESS: Target build #{target_id} is correctly tagged.")
    else:
        feedback.append(f"FAIL: Target build #{target_id} missing tag '{expected_tag}'. Found: '{target_desc}'")

    # CRITERION 2: False Positive Check (Prev/Next builds) (40 pts)
    # This prevents the agent from just tagging all failed builds
    false_positives = 0
    
    if expected_tag.lower() in prev_desc.lower():
        false_positives += 1
        feedback.append(f"FAIL: Build #{data['prev_build_id']} (Success) was incorrectly tagged.")
        
    if expected_tag.lower() in next_desc.lower():
        false_positives += 1
        feedback.append(f"FAIL: Build #{data['next_build_id']} (Subsequent Failure) was incorrectly tagged.")

    if false_positives == 0:
        score += 40
        feedback.append("SUCCESS: No incorrect builds were tagged.")
    elif false_positives == 1:
        score += 10 # Partial credit if they only messed up one neighbor
        feedback.append("PENALTY: One incorrect build was tagged.")
    else:
        # If they tagged everything, major penalty
        if score >= 60:
            score = 20 # Cap score low if they spammed tags
            feedback.append("PENALTY: Multiple incorrect builds tagged. 'Tag All' strategy detected.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }