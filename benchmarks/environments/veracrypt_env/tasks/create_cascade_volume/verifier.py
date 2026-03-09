#!/usr/bin/env python3
"""
Verifier for create_cascade_volume task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cascade_volume(traj, env_info, task_info):
    """
    Verify the creation of a cascaded encryption volume.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error reading result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result file"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Scoring Logic ---

    # 1. Volume Existence & Validity (20 pts)
    # 50MB is 52,428,800 bytes. Allow some overhead tolerance.
    # VeraCrypt container size matches exactly usually, but headers add minimal overhead.
    vol_size = result.get('volume_size_bytes', 0)
    expected_size = 50 * 1024 * 1024 # 52428800
    
    # 1a. Exists and mountable (10 pts)
    if result.get('volume_exists') and result.get('mount_success'):
        score += 10
        feedback_parts.append("Volume created and mountable")
    elif result.get('volume_exists'):
        score += 5
        feedback_parts.append("Volume exists but failed to mount (wrong password?)")
    else:
        feedback_parts.append("Volume file not found")

    # 1b. Correct Size (10 pts)
    # Allow small variance (+/- 1MB)
    if abs(vol_size - expected_size) < 1048576 and vol_size > 0:
        score += 10
    elif vol_size > 0:
        feedback_parts.append(f"Volume size incorrect ({vol_size/1024/1024:.1f}MB vs 50MB)")
    
    # 2. Encryption Settings (30 pts)
    # Note: veracrypt output might be "AES(Twofish(Serpent))" or "AES-Twofish-Serpent"
    enc_algo = result.get('encryption_algo', '').lower()
    hash_algo = result.get('hash_algo', '').lower()
    
    # 2a. Algorithm (15 pts)
    # Check for presence of all three algorithms
    if 'aes' in enc_algo and 'twofish' in enc_algo and 'serpent' in enc_algo:
        score += 15
        feedback_parts.append("Encryption: AES-Twofish-Serpent (Correct)")
    elif enc_algo and enc_algo != 'unknown':
        feedback_parts.append(f"Encryption: {enc_algo} (Incorrect)")
    
    # 2b. Hash (15 pts)
    if 'whirlpool' in hash_algo:
        score += 15
        feedback_parts.append("Hash: Whirlpool (Correct)")
    elif hash_algo and hash_algo != 'unknown':
        feedback_parts.append(f"Hash: {hash_algo} (Incorrect)")

    # 3. Filesystem (10 pts)
    fs = result.get('filesystem', '').lower()
    if 'ext4' in fs:
        score += 10
        feedback_parts.append("Filesystem: ext4 (Correct)")
    elif fs and fs != 'unknown':
        feedback_parts.append(f"Filesystem: {fs} (Incorrect)")

    # 4. File Content Integrity (24 pts)
    files_correct = 0
    if result.get('file1_correct'): files_correct += 1
    if result.get('file2_correct'): files_correct += 1
    if result.get('file3_correct'): files_correct += 1
    
    score += (files_correct * 8)
    if files_correct == 3:
        feedback_parts.append("All files transferred correctly")
    elif files_correct > 0:
        feedback_parts.append(f"{files_correct}/3 files transferred correctly")
    else:
        feedback_parts.append("No files transferred correctly")

    # 5. Dismount State (6 pts)
    if not result.get('agent_left_mounted'):
        score += 6
        feedback_parts.append("Volume properly dismounted")
    else:
        feedback_parts.append("Volume left mounted (should be dismounted)")

    # 6. Report File (10 pts)
    if result.get('report_exists'):
        if result.get('report_content_correct'):
            score += 10
            feedback_parts.append("Report file valid")
        else:
            score += 5
            feedback_parts.append("Report file exists but content mismatch")
    else:
        feedback_parts.append("Report file missing")

    # Pass Condition
    # Must have correct encryption params and > 70 points
    encryption_ok = ('aes' in enc_algo and 'twofish' in enc_algo and 'serpent' in enc_algo)
    hash_ok = ('whirlpool' in hash_algo)
    
    passed = (score >= 70) and encryption_ok and hash_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }