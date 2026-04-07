#!/usr/bin/env python3
"""
Verifier for docker_orphaned_volume_rescue task.

Scoring Criteria:
1. Container 'recovery-service' is running (20 pts)
2. File '/app/data/uploads/critical_manifest.json' exists inside container (40 pts)
3. File content matches the unique ID generated at setup (40 pts)
   - Bonus validation: Checks if the actual original volume was mounted vs data copied.
     (Both pass, but mounting original is preferred style).

Pass threshold: 100 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_volume_rescue(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/volume_rescue_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result file: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Container Running
    if result.get("container_running", 0) == 1:
        score += 20
        feedback.append("Container 'recovery-service' is running. (+20)")
    else:
        feedback.append("Container 'recovery-service' is NOT running. (0/20)")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # Criterion 2: File Exists
    if result.get("file_exists", 0) == 1:
        score += 40
        feedback.append("Target file found inside container. (+40)")
    else:
        feedback.append("Target file 'critical_manifest.json' NOT found in container. (0/40)")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # Criterion 3: Content Match (Proof of work)
    actual = result.get("actual_content", "").strip()
    expected = result.get("expected_content", "").strip()
    
    # Normalize JSON strings for comparison if possible, otherwise string match
    # The setup script generates a JSON string.
    content_match = False
    try:
        if json.loads(actual) == json.loads(expected):
            content_match = True
    except:
        if actual == expected and expected != "":
            content_match = True

    if content_match:
        score += 40
        feedback.append("File content verified successfully. (+40)")
    else:
        feedback.append(f"Content mismatch! Expected ID not found. (0/40)")
        feedback.append(f"Got: {actual[:100]}...")

    # Optional: Check if they mounted the volume or copied data
    # This doesn't change the score (both are valid recoveries), but adds positive feedback
    if result.get("mounted_correct_volume_id", 0) == 1:
        feedback.append("(Perfect: Original volume mounted directly)")
    else:
        feedback.append("(Note: Data recovered, but original volume ID not mounted directly)")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }