#!/usr/bin/env python3
"""
Verifier for retrieve_archive_entry task.
Verifies that the agent recovered the correct configuration string from inside the zip artifact.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retrieve_archive_entry(traj, env_info, task_info):
    """
    Verify the agent retrieved the config file from the archive.
    
    Criteria:
    1. Output file exists (20 pts)
    2. File created during task (10 pts)
    3. Content matches the secret generated during setup (70 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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
    
    # 1. Output file exists
    if result.get("output_exists", False):
        score += 20
        feedback_parts.append("Output file found (+20)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file ~/recovered_config.properties not found"}

    # 2. File created during task
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task session (+10)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it might be stale")

    # 3. Content match
    if result.get("output_match", False):
        score += 70
        feedback_parts.append("Content matches expected secret configuration (+70)")
    else:
        feedback_parts.append("Content does NOT match expected configuration")
        actual = result.get("actual_content_preview", "N/A")
        expected = result.get("expected_content_preview", "N/A")
        feedback_parts.append(f"Expected start: '{expected}', Got: '{actual}'")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }