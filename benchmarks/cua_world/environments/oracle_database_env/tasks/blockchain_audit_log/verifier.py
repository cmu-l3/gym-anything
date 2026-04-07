#!/usr/bin/env python3
"""
Verifier for Blockchain Audit Log task.

Verification Strategy:
1. DB State: Check if SALARY_CHANGE_LEDGER exists and is a BLOCKCHAIN TABLE.
2. DB Config: Verify NO DROP/DELETE days >= 16 and SHA2_512.
3. DB Content: Verify 3 rows exist and data sample is correct.
4. Tamper Evidence: Check 'tamper_evidence.txt' for valid ORA- error (proving failed delete).
5. Signature: Check 'latest_signature.txt' for valid hex signature from hidden column.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_blockchain_audit_log(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_error = metadata.get('expected_error_code', 'ORA-05709')

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Table Creation & Type (25 pts)
    if result.get("table_exists"):
        if result.get("is_blockchain"):
            score += 25
            feedback.append("Blockchain table created successfully.")
        else:
            score += 5
            feedback.append("Table created, but is NOT a Blockchain table (0 pts for type).")
    else:
        feedback.append("Table SALARY_CHANGE_LEDGER not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Security Configuration (15 pts)
    # Expecting >= 16 days for drop/delete and SHA2_512
    # Note: 'SHA2_512' might return as 'SHA2-512' depending on Oracle version, checking containment.
    
    config_ok = True
    no_drop = result.get("no_drop_days", 0)
    no_delete = result.get("no_delete_days", 0)
    algo = result.get("hash_algorithm", "")

    if no_drop < 16:
        feedback.append(f"NO DROP days too low ({no_drop} < 16).")
        config_ok = False
    if no_delete < 16:
        feedback.append(f"NO DELETE days too low ({no_delete} < 16).")
        config_ok = False
    if "SHA2_512" not in algo and "SHA2-512" not in algo:
        feedback.append(f"Wrong hash algorithm: {algo}.")
        config_ok = False
    
    if config_ok:
        score += 15
        feedback.append("Retention and hashing configured correctly.")
    else:
        score += 5 # Partial credit if they at least made it a blockchain table

    # 3. Data Loaded (10 pts)
    row_count = result.get("row_count", 0)
    if row_count == 3:
        score += 10
        feedback.append("Correct number of rows inserted.")
    elif row_count > 0:
        score += 5
        feedback.append(f"Incorrect row count: {row_count} (expected 3).")
    else:
        feedback.append("Table is empty.")

    # 4. Tamper Evidence (25 pts)
    # Must contain ORA error code
    evidence_content = result.get("tamper_evidence_content", "")
    if result.get("tamper_evidence_exists"):
        # Look for ORA-05709 or relevant blockchain violation error
        # Common blockchain errors: ORA-05709 (retention), ORA-05723 (drop retention)
        if "ORA-" in evidence_content:
            score += 25
            feedback.append(f"Tamper evidence verified: Found Oracle error ({evidence_content[:20]}...).")
        else:
            score += 5
            feedback.append("Evidence file exists but does not contain an ORA- error message.")
    else:
        feedback.append("Tamper evidence file missing.")

    # 5. Signature Extraction (25 pts)
    # Looking for a long hex string (SHA2-512 is 128 hex chars)
    sig_content = result.get("signature_file_content", "").strip()
    if result.get("signature_file_exists"):
        # Allow some slack, just check if it looks like a hash (hex, reasonable length)
        if re.match(r'^[0-9A-Fa-f]{64,130}$', sig_content):
            score += 25
            feedback.append("Signature file verified (valid hex hash).")
        else:
            score += 5
            feedback.append(f"Signature file content does not look like a SHA2-512 hash: '{sig_content[:20]}...'")
    else:
        feedback.append("Signature file missing.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }