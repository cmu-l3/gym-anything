#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_encrypt_existing_data(traj, env_info, task_info):
    """
    Verifier for encrypt_existing_data task.
    
    Scoring Breakdown (Total 100):
    - Volume Creation & Params (20 pts): Exists, Size >= 5MB, Timestamp OK, AES/SHA-512
    - Access (15 pts): Mounts with correct password
    - Data Transfer (25 pts): All 4 files present in volume
    - Integrity (15 pts): Checksums match manifest
    - Reporting (15 pts): Transfer report exists and has correct text
    - Cleanup (10 pts): Original files deleted
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # --- Volume Creation & Params (20 pts) ---
    vol_exists = result.get("volume_exists", False)
    vol_size = result.get("volume_size_mb", 0)
    created_new = result.get("created_after_start", False)
    enc_algo = result.get("encryption_algorithm", "")
    hash_algo = result.get("hash_algorithm", "")
    
    if vol_exists:
        score += 5
        if vol_size >= 4: # Allow slight buffer for 5MB requirement
            score += 5
        else:
            feedback_parts.append(f"Volume too small ({vol_size}MB)")
            
        if created_new:
            score += 5
        else:
            feedback_parts.append("Volume file predates task start")
            
        # Check algorithms (loose matching for string variations)
        if "AES" in enc_algo and "SHA-512" in hash_algo:
            score += 5
        elif enc_algo != "unknown": # Only penalize if we successfully read them but they were wrong
            feedback_parts.append(f"Incorrect algo: {enc_algo}/{hash_algo}")
            score += 2 # Partial credit for encryption
    else:
        feedback_parts.append("Encrypted volume not found")

    # --- Access (15 pts) ---
    if result.get("mount_success", False):
        score += 15
    elif vol_exists:
        feedback_parts.append("Volume exists but failed to mount with password 'SecureEncrypt2024!'")

    # --- Data Transfer (25 pts) ---
    # 4 files expected: NDA, Budget, Keys, Manifest
    files_found = result.get("files_found_count", 0)
    # 6.25 points per file, integer math: 6 * 4 = 24 + 1 bonus if all
    score += (files_found * 6)
    if files_found == 4:
        score += 1
    elif vol_exists:
        feedback_parts.append(f"Only {files_found}/4 files found in volume")

    # --- Integrity (15 pts) ---
    if result.get("integrity_match", False):
        score += 15
    elif files_found > 0:
        feedback_parts.append("File integrity check failed (checksum mismatch)")

    # --- Reporting (15 pts) ---
    report_found = result.get("report_found", False)
    report_ok = result.get("report_content_ok", False)
    
    if report_found:
        score += 5
        if report_ok:
            score += 10
        else:
            feedback_parts.append("Report found but missing required text")
    else:
        feedback_parts.append("Transfer report missing")

    # --- Cleanup (10 pts) ---
    if result.get("originals_deleted", False):
        score += 10
    else:
        feedback_parts.append("Original unencrypted files still exist")

    # 4. Final Verification
    passed = (score >= 65) # Threshold defined in spec
    
    if not feedback_parts:
        feedback_parts.append("Perfect execution")
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }