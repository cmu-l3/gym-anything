#!/usr/bin/env python3
"""
Verifier for Autonomous Transaction Logging task.

Criteria:
1. Log Persistence (30 pts): 'Insufficient funds' log exists in DB despite rollback.
2. Data Integrity (20 pts): Sender balance matches initial state (1000).
3. Pragma Usage (30 pts): `PRAGMA AUTONOMOUS_TRANSACTION` found in PL/SQL source.
4. Modular Design (10 pts): A separate logging procedure exists (not just inline).
5. Evidence File (10 pts): Output file exists on Desktop.

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_autonomous_logging(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_path)
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve or parse results: {str(e)}"
            }

    score = 0
    feedback = []

    # 1. Log Persistence (30 pts)
    if result.get("logs_found", False):
        score += 30
        feedback.append("SUCCESS: Failure log persisted in database.")
    else:
        feedback.append("FAIL: No 'Insufficient funds' log found in database.")

    # 2. Data Integrity (20 pts)
    balance = result.get("sender_balance", -1)
    if result.get("balance_correct", False):
        score += 20
        feedback.append(f"SUCCESS: Account balance rolled back correctly to {balance}.")
    else:
        feedback.append(f"FAIL: Account balance incorrect ({balance}). Expected 1000.")

    # 3. Pragma Usage (30 pts)
    if result.get("pragma_found", False):
        score += 30
        feedback.append("SUCCESS: PRAGMA AUTONOMOUS_TRANSACTION detected in code.")
    else:
        feedback.append("FAIL: PRAGMA AUTONOMOUS_TRANSACTION not found in user source.")

    # 4. Modular Design (10 pts)
    if result.get("logging_proc_exists", False):
        score += 10
        feedback.append("SUCCESS: Separate logging procedure detected.")
    else:
        feedback.append("WARNING: Logging logic appears to be inline or missing separate procedure.")

    # 5. Evidence File (10 pts)
    if result.get("evidence_file_exists", False):
        content = result.get("evidence_file_content", "")
        if "Insufficient" in content or "ERROR" in content:
            score += 10
            feedback.append("SUCCESS: Evidence file contains log data.")
        else:
            score += 5
            feedback.append("PARTIAL: Evidence file exists but may rely on generic export.")
    else:
        feedback.append("FAIL: Evidence file /home/ga/Desktop/audit_evidence.txt not found.")

    passed = score >= 60 and result.get("logs_found", False) and result.get("balance_correct", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }