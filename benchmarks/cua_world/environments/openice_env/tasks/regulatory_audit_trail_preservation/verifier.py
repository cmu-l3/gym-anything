#!/usr/bin/env python3
"""
Verifier for Regulatory Audit Trail Preservation task.

Verifies:
1. Audit directory creation.
2. Clinical session execution (via preserved log content).
3. Log file preservation.
4. Cryptographic integrity (SHA-256 hash match).
5. Manifest creation and content.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_regulatory_audit_trail_preservation(traj, env_info, task_info):
    # Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # 1. Audit Directory (10 pts)
    if result.get("dir_exists", False):
        score += 10
        feedback_parts.append("Audit directory created")
    else:
        feedback_parts.append("Audit directory missing")

    # 2. Log File Preservation (20 pts)
    log_exists = result.get("log_exists", False)
    log_size = result.get("log_size", 0)
    task_start = result.get("task_start_timestamp", 0)
    log_mtime = result.get("log_mtime", 0)
    
    file_created_during_task = int(log_mtime) > int(task_start)
    
    if log_exists and log_size > 0:
        if file_created_during_task:
            score += 20
            feedback_parts.append("Log file preserved correctly")
        else:
            score += 10
            feedback_parts.append("Log file exists but timestamp suggests it wasn't created during task")
    else:
        feedback_parts.append("Log file missing or empty")

    # 3. Log Content Validity (20 pts)
    # Checks if the preserved log actually contains the requested clinical device data
    has_multi = result.get("contains_multiparam", False)
    has_infusion = result.get("contains_infusion", False)
    
    if has_multi and has_infusion:
        score += 20
        feedback_parts.append("Log contains evidence of both devices")
    elif has_multi or has_infusion:
        score += 10
        feedback_parts.append("Log contains evidence of only one device")
    else:
        feedback_parts.append("Log does not contain required device activity")

    # 4. Integrity Hash Check (25 pts)
    hash_exists = result.get("hash_file_exists", False)
    hash_matches = result.get("hash_matches", False)
    
    if hash_exists:
        if hash_matches:
            score += 25
            feedback_parts.append("SHA-256 hash valid and matches log file")
        else:
            score += 10
            feedback_parts.append("Hash file exists but checksum DOES NOT match log file")
    else:
        feedback_parts.append("Hash file missing")

    # 5. Manifest Check (15 pts)
    manifest_exists = result.get("manifest_exists", False)
    manifest_valid = result.get("manifest_has_devices", False)
    
    if manifest_exists:
        if manifest_valid:
            score += 15
            feedback_parts.append("Manifest created with correct content")
        else:
            score += 5
            feedback_parts.append("Manifest exists but missing device details")
    else:
        feedback_parts.append("Manifest missing")

    # 6. OpenICE Running (10 pts)
    if result.get("openice_running", False):
        score += 10
    else:
        feedback_parts.append("OpenICE not running at end")

    # Final Pass/Fail
    # Must have preserved a valid log and generated a matching hash to pass
    passed = (score >= 65) and log_exists and hash_matches

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }