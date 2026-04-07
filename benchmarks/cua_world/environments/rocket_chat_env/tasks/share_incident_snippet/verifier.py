#!/usr/bin/env python3
"""Verifier for share_incident_snippet task."""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_share_incident_snippet(traj, env_info, task_info):
    """
    Verify that the user shared the required code snippet.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_content = metadata.get('expected_content', "")
    expected_content_lines = [line.strip() for line in expected_content.strip().split("\n")]

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
    feedback = []

    file_found = result.get("file_found", False)
    is_new = result.get("is_new", False)
    file_content = result.get("file_content", "")

    if not file_found:
        feedback.append("File 'rollback_procedure.sh' not found in #release-updates channel.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    score += 30
    feedback.append("File 'rollback_procedure.sh' found in channel.")

    if is_new:
        score += 20
        feedback.append("File was created during the task.")
    else:
        feedback.append("File was NOT created during the task (may be from a previous session).")

    # Verify content
    actual_content_lines = [line.strip() for line in file_content.strip().split("\n")]
    
    # We allow some tolerance for extra newlines at start/end by matching non-empty content
    if "\n".join(actual_content_lines) == "\n".join(expected_content_lines):
        score += 50
        feedback.append("File content exactly matches expected script.")
    else:
        # Partial match
        matched_lines = sum(1 for line in expected_content_lines if line in actual_content_lines)
        if len(expected_content_lines) > 0:
            match_ratio = matched_lines / len(expected_content_lines)
            content_score = int(50 * match_ratio)
            score += content_score
            feedback.append(f"File content partially matches ({match_ratio:.0%} of expected lines found).")
        else:
            feedback.append("Expected content was empty (configuration error).")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }