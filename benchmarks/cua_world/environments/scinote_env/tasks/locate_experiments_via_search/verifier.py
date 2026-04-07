#!/usr/bin/env python3
"""Verifier for locate_experiments_via_search task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_locate_experiments_via_search(traj, env_info, task_info):
    """Verify that the agent searched for Vorinostat and recorded the correct experiments."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available - framework error"}

    metadata = task_info.get('metadata', {})
    expected_output_file = metadata.get('expected_output_file', '/home/ga/Documents/vorinostat_experiments.txt')
    expected_exps = metadata.get('expected_experiments', [
        "Efficacy Study VR-01",
        "PK Profile - Group 4",
        "Toxicity Screening 2024"
    ])

    # Copy task result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    file_exists = result.get('file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)

    # Criterion 1: File Exists (10 points)
    if file_exists:
        score += 10
        feedback_parts.append("Output text file exists")
        
        if file_created_during_task:
            feedback_parts.append("(Created during task)")
        else:
            feedback_parts.append("(WARNING: File timestamp precedes task start)")
    else:
        feedback_parts.append("Output text file not found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Extract contents of the output file
    file_content = ""
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(expected_output_file, temp_txt.name)
        with open(temp_txt.name, 'r') as f:
            file_content = f.read().lower()
    except Exception as e:
        logger.error(f"Could not read text file from env: {e}")
        feedback_parts.append(f"Could not read text file from env: {e}")
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # Criteria 2-4: Check for presence of each expected experiment (30 points each)
    found_count = 0
    for exp in expected_exps:
        if exp.lower() in file_content:
            found_count += 1
            score += 30
            feedback_parts.append(f"Found match for: '{exp}'")
        else:
            feedback_parts.append(f"Missing match for: '{exp}'")

    # Pass if the file is created and at least 2 out of 3 experiments are found
    passed = file_exists and found_count >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "file_exists": file_exists,
            "found_exp_1": expected_exps[0].lower() in file_content,
            "found_exp_2": expected_exps[1].lower() in file_content,
            "found_exp_3": expected_exps[2].lower() in file_content
        }
    }