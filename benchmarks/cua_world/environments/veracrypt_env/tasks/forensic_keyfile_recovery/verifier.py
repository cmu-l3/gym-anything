#!/usr/bin/env python3
"""
Verifier for forensic_keyfile_recovery task.

Scoring Criteria:
1. Evidence Recovery (70 pts): 'prototype_specs.txt' recovered with correct hash.
2. Keyfile Identification (10 pts): Correct keyfile name written to report.
3. Mount Success (20 pts): Volume successfully mounted (implied by recovery or active mount).

Total: 100 points
Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forensic_keyfile_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Evidence Recovery (70 points)
    file_exists = result.get('file_exists', False)
    file_hash = result.get('file_hash', '')
    expected_hash = result.get('expected_hash', 'unknown')
    
    if file_exists:
        if file_hash == expected_hash:
            score += 70
            feedback_parts.append("✅ Evidence recovered successfully (Integrity Verified)")
        else:
            # Partial credit for file existence but wrong content (unlikely in this task but possible)
            score += 10
            feedback_parts.append(f"⚠️ Recovered file exists but content mismatch (Hash: {file_hash} != {expected_hash})")
    else:
        feedback_parts.append("❌ Evidence file not found in recovery directory")

    # 2. Verify Keyfile Identification (10 points)
    report_exists = result.get('report_exists', False)
    reported_keyfile = result.get('reported_keyfile', '')
    actual_keyfile = result.get('actual_keyfile', '')
    
    if report_exists:
        # Check if the reported name contains the actual keyfile name (case-insensitive)
        if actual_keyfile.lower() in reported_keyfile.lower() and len(reported_keyfile) < 50:
            score += 10
            feedback_parts.append(f"✅ Correct keyfile identified: {actual_keyfile}")
        else:
            feedback_parts.append(f"❌ Incorrect keyfile reported (Expected: {actual_keyfile}, Got: {reported_keyfile})")
    else:
        feedback_parts.append("ℹ️ Keyfile identification report not found (Optional)")

    # 3. Verify Mount Success (20 points)
    # If they recovered the file with correct hash, they MUST have mounted it.
    # Otherwise check if it is currently mounted.
    if score >= 70:
        score += 20
        feedback_parts.append("✅ Volume mount confirmed via successful recovery")
    elif result.get('volume_mounted', False):
        score += 20
        feedback_parts.append("✅ Volume is currently mounted (but evidence not moved)")
    else:
        feedback_parts.append("❌ Volume not mounted")

    # Final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }