#!/usr/bin/env python3
"""
Verifier for implement_address_audit_trigger task.

Scoring Criteria:
1. SQL Implementation File Exists (10 pts)
2. Audit Table Created (20 pts)
3. Trigger Created (20 pts)
4. Functional Test: Trigger logs updates correctly (40 pts)
5. Data Integrity: Logged values match old/new address (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_address_audit_trigger(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check SQL File (10 pts)
    if result.get("sql_file_exists"):
        score += 10
        feedback_parts.append("SQL implementation file saved")
    else:
        feedback_parts.append("SQL implementation file missing")

    # Parse DB Verification results
    db_res = result.get("db_verification", {})
    if db_res.get("error"):
        feedback_parts.append(f"Database check failed: {db_res['error']}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Table Exists (20 pts)
    if db_res.get("table_exists"):
        score += 10
        feedback_parts.append("Audit table exists")
        if db_res.get("columns_correct"):
            score += 10
            feedback_parts.append("Table structure correct")
        else:
            feedback_parts.append("Table missing required columns")
    else:
        feedback_parts.append("Audit table NOT found")

    # 3. Trigger Exists (20 pts)
    if db_res.get("trigger_exists"):
        score += 20
        feedback_parts.append("Trigger created")
    else:
        feedback_parts.append("Trigger NOT found")

    # 4. Functional Test (40 pts)
    if db_res.get("functional_test_passed"):
        score += 40
        feedback_parts.append("Trigger successfully logs address changes")
    else:
        feedback_parts.append("Trigger FAILED functional test (no log created on update)")

    # 5. Data Integrity (10 pts)
    if db_res.get("data_integrity_passed"):
        score += 10
        feedback_parts.append("Logged data matches expected values")
    elif db_res.get("functional_test_passed"):
        feedback_parts.append("Log created but data values mismatch")

    passed = score >= 70 and db_res.get("functional_test_passed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }