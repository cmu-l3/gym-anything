#!/usr/bin/env python3
"""
Verifier for audit_weak_passwords task.

Scoring Criteria:
1. Vulnerable Volume Secured (50 pts): 'archive_bravo.hc' mounts with 'Audited&Secured#2026'.
2. Old Password Revoked (30 pts): 'archive_bravo.hc' NO LONGER mounts with 'princess'.
3. Correct Reporting (10 pts): JSON report identifies 'archive_bravo.hc'.
4. Integrity (10 pts): Other volumes ('alpha', 'charlie') remain accessible with original credentials.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_weak_passwords(traj, env_info, task_info):
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
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result file"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Vulnerable Volume Secured (50 pts)
    # The export script has already tried to mount with the new password
    if result.get("vulnerable_vol_new_pwd_works", False):
        score += 50
        feedback_parts.append("✅ Vulnerable volume secured with new password")
    else:
        feedback_parts.append("❌ Vulnerable volume NOT mountable with new password")

    # 2. Old Password Revoked (30 pts)
    # The export script tried to mount with 'princess'. It should fail (false).
    old_pwd_works = result.get("vulnerable_vol_old_pwd_works", True)
    if not old_pwd_works:
        score += 30
        feedback_parts.append("✅ Old weak password revoked")
    else:
        feedback_parts.append("❌ Old weak password still works!")

    # 3. Report Verification (10 pts)
    report_content = result.get("report_content", {})
    report_exists = result.get("report_exists", False)
    
    if report_exists:
        # Check if they identified the correct volume
        # Accept 'archive_bravo.hc' or full path
        vol_name = report_content.get("vulnerable_volume", "")
        weak_pwd = report_content.get("weak_password_found", "")
        
        if "archive_bravo" in vol_name:
            score += 5
            feedback_parts.append("✅ Report correctly identified volume")
        else:
            feedback_parts.append(f"❌ Report identified wrong volume: {vol_name}")
            
        if weak_pwd == "princess":
            score += 5
            feedback_parts.append("✅ Report correctly identified weak password")
        else:
             feedback_parts.append(f"❌ Report identified wrong password: {weak_pwd}")
    else:
        feedback_parts.append("❌ No audit report found")

    # 4. Integrity Check (10 pts)
    # Alpha and Charlie must still work
    alpha_ok = result.get("alpha_integrity", False)
    charlie_ok = result.get("charlie_integrity", False)
    
    if alpha_ok and charlie_ok:
        score += 10
        feedback_parts.append("✅ Non-vulnerable volumes intact")
    else:
        feedback_parts.append("⚠️ Warning: Non-vulnerable volumes modified or corrupted")

    # Pass threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }