#!/usr/bin/env python3
"""Verifier for recover_access_with_candidate_passwords task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_recover_access(traj, env_info, task_info):
    """
    Verify that the agent successfully recovered the file and identified the password.
    
    Scoring:
    - Access Recovered (File exists): 40 pts
    - Data Integrity (Hash match): 30 pts
    - Credential Identified (Correct password text): 20 pts
    - Cleanup (Volume dismounted): 10 pts
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
            copy_from_env("/tmp/recovery_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # 1. Access Recovered (40 pts)
        if result.get('recovered_file_exists'):
            # Check timestamps to prevent gaming
            if result.get('created_during_task'):
                score += 40
                feedback_parts.append("File recovered successfully")
            else:
                feedback_parts.append("File exists but has old timestamp (pre-existing?)")
        else:
            feedback_parts.append("Recovered file NOT found")

        # 2. Data Integrity (30 pts)
        actual_hash = result.get('recovered_file_hash', '')
        expected_hash = result.get('expected_hash', 'unknown')
        
        if result.get('recovered_file_exists'):
            if actual_hash == expected_hash and expected_hash != 'unknown':
                score += 30
                feedback_parts.append("File integrity verified (checksum match)")
            else:
                feedback_parts.append("File integrity check FAILED (checksum mismatch)")

        # 3. Credential Identified (20 pts)
        identified = result.get('identified_password', '')
        correct = result.get('correct_password', '')
        
        if result.get('password_file_exists'):
            if identified == correct and correct != '':
                score += 20
                feedback_parts.append("Correct password identified")
            else:
                feedback_parts.append(f"Wrong password identified (Submitted: '{identified}')")
        else:
            feedback_parts.append("Password text file not created")

        # 4. Cleanup (10 pts)
        if not result.get('volume_still_mounted'):
            score += 10
            feedback_parts.append("Volume cleanly dismounted")
        else:
            feedback_parts.append("Volume was left mounted")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Pass threshold: 70 points
    # Must at least have recovered the correct file (40+30 = 70)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }