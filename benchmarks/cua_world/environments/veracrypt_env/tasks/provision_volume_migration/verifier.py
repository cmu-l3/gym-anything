#!/usr/bin/env python3
"""Verifier for provision_volume_migration task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provision_volume_migration(traj, env_info, task_info):
    """
    Verify the provision_volume_migration task.
    
    Scoring Criteria:
    - Volume Created (10 pts): File exists.
    - Mount Success (20 pts): Mounts with correct password.
    - Algorithm Compliance (30 pts): Algorithm is 'Serpent'. (Anti-gaming: prevents just copying the AES template)
    - Data Integrity (30 pts): All files present and content matches.
    - Clean State (10 pts): No volumes left mounted.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/provision_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error reading result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Volume Created (10 pts)
    if result.get('volume_exists'):
        score += 10
        feedback_parts.append("Target volume created")
    else:
        feedback_parts.append("Target volume NOT found")
        return {"passed": False, "score": 0, "feedback": "Target volume not found"}

    # Criterion 2: Mount Success (20 pts)
    if result.get('mount_success'):
        score += 20
        feedback_parts.append("Volume mounted successfully")
    else:
        feedback_parts.append("Volume failed to mount with specified password")
        # Cannot verify further if mount fails
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Algorithm Compliance (30 pts)
    detected_algo = result.get('detected_algorithm', 'Unknown')
    if result.get('algorithm_correct'):
        score += 30
        feedback_parts.append(f"Correct algorithm used ({detected_algo})")
    else:
        feedback_parts.append(f"Incorrect algorithm: {detected_algo} (Expected: Serpent)")

    # Criterion 4: Data Integrity (30 pts)
    if result.get('files_integrity_match'):
        score += 30
        feedback_parts.append("All data migrated and verified")
    elif result.get('files_copied'):
        score += 10
        feedback_parts.append("Files copied but checksums mismatch")
    else:
        feedback_parts.append("Files missing from new volume")

    # Criterion 5: Clean State (10 pts)
    if result.get('clean_state'):
        score += 10
        feedback_parts.append("Cleanup correct (all volumes dismounted)")
    else:
        count = result.get('leftover_mount_count', '?')
        feedback_parts.append(f"Volumes left mounted ({count})")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }