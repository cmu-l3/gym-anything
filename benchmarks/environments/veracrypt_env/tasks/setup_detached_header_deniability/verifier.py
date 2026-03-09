#!/usr/bin/env python3
"""Verifier for setup_detached_header_deniability task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detached_header(traj, env_info, task_info):
    """
    Verify the detached header configuration.
    
    Scoring:
    - Volume & Header files exist: 20 pts
    - Primary header wiped (standard mount fails): 20 pts
    - Backup header wiped (backup mount fails): 20 pts
    - Volume mounts with external header: 30 pts
    - Data is intact inside: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/detached_header_result.json", temp_result.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification results"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # 1. File Existence (20 pts)
        if result.get('volume_exists') and result.get('header_exists'):
            score += 20
            feedback_parts.append("Files created")
        elif result.get('volume_exists'):
            score += 10
            feedback_parts.append("Volume created but header backup missing")
        else:
            feedback_parts.append("Volume file not found")

        # 2. Primary Header Wiped (20 pts)
        if result.get('primary_header_wiped'):
            score += 20
            feedback_parts.append("Primary header successfully wiped")
        else:
            feedback_parts.append("Primary header still active (standard mount shouldn't work)")

        # 3. Backup Header Wiped (20 pts)
        if result.get('backup_header_wiped'):
            score += 20
            feedback_parts.append("Backup header successfully wiped")
        else:
            feedback_parts.append("Embedded backup header still active")

        # 4. External Mount Works (30 pts)
        if result.get('external_mount_works'):
            score += 30
            feedback_parts.append("Mounting with external header works")
        else:
            feedback_parts.append("Failed to mount using external header")

        # 5. Data Intact (10 pts)
        if result.get('data_intact'):
            score += 10
            feedback_parts.append("Data recovered successfully")
        else:
            if result.get('external_mount_works'):
                feedback_parts.append("Volume mounted but data file missing")
            else:
                feedback_parts.append("Data verification skipped (mount failed)")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    passed = score >= 80
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }