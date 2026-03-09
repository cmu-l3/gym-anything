#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_data_migration(traj, env_info, task_info):
    """
    Verifies the secure data migration task.
    
    Scoring Criteria:
    - Volume Creation & Specs (20 pts)
    - Data Integrity (40 pts)
    - Verification Report (17 pts)
    - Security Hygiene (Clean up + Dismount) (13 pts)
    - Operational Security (Created during task) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result_final.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Volume Existence and Properties (Max 20 + 10 pts)
    if result.get('volume_exists'):
        # Check size (Should be ~25MB, allowing slight overhead variance)
        size_mb = result.get('volume_size_bytes', 0) / (1024 * 1024)
        if 24 <= size_mb <= 26:
            score += 12
            feedback.append("Volume created with correct size (25MB)")
        else:
            score += 5
            feedback.append(f"Volume created but incorrect size ({size_mb:.2f}MB)")
            
        # Check Encryption Specs
        algo = result.get('encryption_algorithm', '').lower()
        hash_algo = result.get('hash_algorithm', '').lower()
        
        if 'aes' in algo and 'sha-512' in hash_algo:
            score += 8
            feedback.append("Encryption parameters correct (AES/SHA-512)")
        else:
            feedback.append(f"Incorrect encryption parameters: {algo}/{hash_algo}")
            
        # Anti-gaming: Created during task
        if result.get('volume_created_during_task'):
            score += 10
        else:
            feedback.append("Volume timestamp predates task start (Pre-existing volume used?)")
    else:
        feedback.append("Volume file not found at expected path")

    # 2. Data Integrity (Max 40 pts)
    if result.get('mount_success'):
        score += 10
        feedback.append("Volume mountable with correct password")
        
        present_count = result.get('files_present_count', 0)
        match_count = result.get('checksums_match_count', 0)
        
        # 4 pts per file present (5 files = 20 pts)
        score += (present_count * 4)
        if present_count == 5:
            feedback.append("All 5 files present in volume")
        else:
            feedback.append(f"Only {present_count}/5 files found in volume")
            
        # 2 pts per checksum match (5 files = 10 pts)
        score += (match_count * 2)
        if match_count == 5:
            feedback.append("All file checksums verified integrity")
        elif match_count < present_count:
            feedback.append("Some files corrupted or modified")
    else:
        feedback.append("Failed to mount volume (Wrong password or corrupted)")

    # 3. Migration Report (Max 17 pts)
    if result.get('report_exists'):
        score += 8
        feedback.append("Migration report found")
        
        if result.get('report_has_checksums'):
            score += 5
            feedback.append("Report contains checksums")
        else:
            feedback.append("Report missing checksum data")
            
        if result.get('report_has_pass'):
            score += 4
            feedback.append("Report indicates PASS status")
    else:
        feedback.append("Migration report not created")

    # 4. Security Hygiene (Max 13 pts)
    if result.get('originals_removed'):
        score += 8
        feedback.append("Original unencrypted files securely removed")
    else:
        feedback.append("Original files still present on disk")
        
    if not result.get('final_volumes_mounted'):
        score += 5
        feedback.append("Volume correctly dismounted")
    else:
        feedback.append("Volume left mounted (Security risk)")

    # Final Calculation
    passed = score >= 60 and result.get('mount_success') and result.get('files_present_count', 0) >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }