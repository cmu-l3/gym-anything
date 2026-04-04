#!/usr/bin/env python3
"""
Verifier for recover_volume_with_unknown_keyfile task.

Criteria:
1. Volume must be mounted at the correct location (40 pts)
2. Secret token must be recovered and match ground truth (30 pts)
3. Correct keyfile name must be identified in output file (30 pts)

Anti-gaming:
- Checks that output files were created during the task window.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_recover_volume(traj, env_info, task_info):
    """
    Verify the agent recovered the volume using the unknown keyfile.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []

    # Criterion 1: Volume Mounted (40 pts)
    if result.get('is_mounted', False):
        score += 40
        feedback_parts.append("Volume mounted successfully (40 pts)")
    else:
        feedback_parts.append("Volume NOT mounted")

    # Criterion 2: Token Recovered (30 pts)
    if result.get('token_match', False):
        score += 30
        feedback_parts.append("Token recovered correctly (30 pts)")
    elif result.get('token_file_exists', False):
        feedback_parts.append("Token file exists but content incorrect")
    else:
        feedback_parts.append("Token file not found")

    # Criterion 3: Keyfile Identified (30 pts)
    if result.get('keyfile_match', False):
        score += 30
        feedback_parts.append(f"Correct keyfile identified: {result.get('expected_keyname')} (30 pts)")
    elif result.get('keyfile_report_exists', False):
        feedback_parts.append(f"Wrong keyfile identified (Expected: {result.get('expected_keyname')}, Got: {result.get('actual_keyname')})")
    else:
        feedback_parts.append("Keyfile name report not found")

    # Anti-gaming check
    if not result.get('files_created_during_task', False) and (result.get('token_file_exists') or result.get('keyfile_report_exists')):
        feedback_parts.append("WARNING: Output files appear to be stale (not created during task)")
        # We penalize by capping score if it looks suspicious, or just warning.
        # For strictness:
        if score > 0:
            score = 0
            feedback_parts.append("Failed anti-gaming check: Files pre-dated task start")

    passed = score >= 70  # Pass if mount + token OR mount + keyfile (proving work was done)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }