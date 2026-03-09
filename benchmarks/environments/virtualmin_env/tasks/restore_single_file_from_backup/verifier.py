#!/usr/bin/env python3
"""
Verifier for restore_single_file_from_backup task.

Verification Logic:
1. Target Restoration (50pts): 'pricing.pdf' exists AND matches the MD5 of the original file (from ground truth).
2. Data Preservation (50pts): 'index.html' exists AND matches the MD5 of the NEW version (created during setup).
   - If 'index.html' matches the OLD version (from backup), the agent failed to protect recent changes -> 0 points for this section.
   - If 'index.html' is missing or has some random hash -> 0 points.
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_single_file_from_backup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON from Export Script
    result_data = {}
    with tempfile.NamedTemporaryFile(delete=True, suffix='.json') as temp_result:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            temp_result.seek(0)
            result_data = json.load(temp_result)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # 2. Retrieve Ground Truth Hashes
    hashes_data = {}
    with tempfile.NamedTemporaryFile(delete=True, suffix='.json') as temp_hashes:
        try:
            copy_from_env("/home/ga/.ground_truth_hashes.json", temp_hashes.name)
            temp_hashes.seek(0)
            hashes_data = json.load(temp_hashes)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth hashes: {str(e)}"}

    expected_pdf_md5 = hashes_data.get("pdf_original_md5")
    expected_index_new_md5 = hashes_data.get("index_new_md5")
    expected_index_old_md5 = hashes_data.get("index_old_md5")

    # --- CRITERION 1: RESTORE TARGET FILE (50 pts) ---
    target_exists = result_data.get("target_exists", False)
    target_md5 = result_data.get("target_md5", "")

    if target_exists and target_md5 == expected_pdf_md5:
        score += 50
        feedback_parts.append("Success: 'pricing.pdf' restored correctly.")
    elif target_exists:
        # File exists but wrong content (unlikely for a restore, but maybe they created a dummy file)
        score += 10
        feedback_parts.append("Partial: 'pricing.pdf' exists but content does not match backup.")
    else:
        feedback_parts.append("Fail: 'pricing.pdf' was not restored.")

    # --- CRITERION 2: PRESERVE RECENT CHANGES (50 pts) ---
    protected_exists = result_data.get("protected_exists", False)
    protected_md5 = result_data.get("protected_md5", "")

    if protected_exists:
        if protected_md5 == expected_index_new_md5:
            score += 50
            feedback_parts.append("Success: 'index.html' preserved (recent changes kept).")
        elif protected_md5 == expected_index_old_md5:
            # They overwrote it with the backup version
            score += 0 
            feedback_parts.append("Fail: 'index.html' was overwritten by the backup! Recent changes were lost.")
        else:
            # File exists but is neither new nor old (maybe they edited it?)
            score += 10
            feedback_parts.append("Partial: 'index.html' exists but content is unexpected.")
    else:
        score += 0
        feedback_parts.append("Fail: 'index.html' is missing.")

    # --- FINAL CHECK ---
    passed = (score >= 100)  # Strict pass - data loss is not acceptable
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }