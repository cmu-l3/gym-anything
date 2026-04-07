#!/usr/bin/env python3
"""
Verifier for patient_data_encryption task.

Scoring Criteria:
1. Key Management (8 pts): ENCRYPTION_KEY_STORE exists with 32-byte key.
2. Functions (20 pts): ENCRYPT/DECRYPT functions exist and are VALID.
3. Schema Changes (24 pts): Encrypted columns exist (RAW), plaintext dropped.
4. Data Migration (17 pts): 150 rows populated with encrypted data.
5. Functional Verification (18 pts): Decryption function returns valid SSN format.
6. Usability (13 pts): View exists with correct data count, Report file exists.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_patient_data_encryption(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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
    feedback = []

    # 1. Key Management (8 pts)
    if result.get("keystore_exists") and result.get("key_valid"):
        score += 8
        feedback.append("Key store created with valid 256-bit key (+8)")
    elif result.get("keystore_exists"):
        score += 4
        feedback.append("Key store created but key invalid or missing (+4)")
    else:
        feedback.append("Key store table missing (0)")

    # 2. Functions (20 pts)
    if result.get("encrypt_func_valid"):
        score += 10
        feedback.append("ENCRYPT_VALUE function valid (+10)")
    if result.get("decrypt_func_valid"):
        score += 10
        feedback.append("DECRYPT_VALUE function valid (+10)")

    # 3. Schema Changes (24 pts total)
    # 14 pts for encrypted columns existing and being RAW
    if result.get("ssn_encrypted_col_exists") and "RAW" in result.get("ssn_encrypted_type", ""):
        score += 7
        feedback.append("SSN_ENCRYPTED column correct (+7)")
    
    if result.get("diag_encrypted_col_exists"):
        score += 7
        feedback.append("DIAGNOSIS_ENCRYPTED column exists (+7)")
    
    # 10 pts for dropping plaintext
    if result.get("ssn_plaintext_dropped") and result.get("diag_plaintext_dropped"):
        score += 10
        feedback.append("Plaintext columns dropped successfully (+10)")
    else:
        feedback.append("Warning: Plaintext columns still exist (0 for cleanup)")

    # 4. Data Migration (17 pts)
    count = result.get("encrypted_data_count", 0)
    if count >= 150:
        score += 17
        feedback.append(f"All 150 rows migrated (+17)")
    elif count > 0:
        score += int(17 * (count / 150))
        feedback.append(f"Partial migration: {count}/150 rows (+{int(17 * (count / 150))})")

    # 5. Functional Verification (18 pts)
    if result.get("decryption_test_passed"):
        score += 18
        feedback.append("Decryption verification passed: Data roundtrips correctly (+18)")
    else:
        feedback.append("Decryption verification failed (0)")

    # 6. Usability (13 pts)
    if result.get("view_exists") and result.get("view_count", 0) >= 150:
        score += 8
        feedback.append("View created correctly (+8)")
    
    if result.get("report_exists") and result.get("report_size", 0) > 50:
        score += 5
        feedback.append("Report file created (+5)")

    return {
        "passed": score >= 55,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }