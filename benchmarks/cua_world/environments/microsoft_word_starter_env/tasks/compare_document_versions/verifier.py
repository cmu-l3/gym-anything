#!/usr/bin/env python3
"""
Verifier for compare_document_versions task.
Checks if the final document exists, has no tracked changes, and contains/excludes specific text
corresponding to accepted/rejected changes defined in the task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compare_document_versions(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_result.name)
        with open(temp_result.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Parse Result Data
    file_exists = result.get("file_exists", False)
    file_is_new = result.get("file_is_new", False)
    revisions_remaining = result.get("revisions_remaining", -1)
    content = result.get("content_extract", "")

    feedback_log = []
    score = 0
    
    # 3. Evaluate Criteria
    
    # Crit 1: File Existence & Timestamp (10 pts)
    if file_exists and file_is_new:
        score += 10
        feedback_log.append("Final document saved correctly.")
    else:
        feedback_log.append("Final document missing or not saved as a new file.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_log)}

    # Crit 2: No Tracked Changes Remaining (8 pts)
    if revisions_remaining == 0:
        score += 8
        feedback_log.append("Clean document (no tracked changes).")
    elif revisions_remaining > 0:
        feedback_log.append(f"Document still has {revisions_remaining} tracked changes pending.")
    else:
        feedback_log.append("Could not verify tracked changes count.")

    # Content Checks (82 pts total)
    # Define text snippets for Accept/Reject logic
    
    # ACCEPTED CHANGES CHECKS
    # (a) Title: "Business Continuity and Disaster Recovery Plan" (12 pts)
    if "Business Continuity and Disaster Recovery Plan" in content:
        score += 12
        feedback_log.append("Title change accepted.")
    else:
        feedback_log.append("FAIL: Title change incorrect.")

    # (b) RTO: "24 hours" present, "48 hours" absent (12 pts)
    if "24 hours" in content and "48 hours" not in content:
        score += 12
        feedback_log.append("RTO update accepted.")
    else:
        feedback_log.append("FAIL: RTO update incorrect (expected 24h).")

    # (c) "Division managers" present, "Department heads" absent (12 pts)
    if "Division managers" in content and "Department heads" not in content:
        score += 12
        feedback_log.append("Roles update accepted.")
    else:
        feedback_log.append("FAIL: Roles update incorrect.")

    # (d) "automated notification system" present (10 pts)
    if "automated notification system" in content:
        score += 10
        feedback_log.append("Notification method update accepted.")
    else:
        feedback_log.append("FAIL: Notification method update missing.")

    # (e) "cloud-based backup" paragraph present (10 pts)
    if "cloud-based backup" in content.lower():
        score += 10
        feedback_log.append("Cloud backup section accepted.")
    else:
        feedback_log.append("FAIL: Cloud backup section missing.")

    # REJECTED CHANGES CHECKS (Must match ORIGINAL text)
    # (f) "Annual testing... shall be conducted" PRESENT (13 pts)
    # (The revision deleted this, so rejection means it must still be there)
    if "Annual testing of the disaster recovery procedures shall be conducted" in content:
        score += 13
        feedback_log.append("Testing requirement deletion correctly REJECTED (text preserved).")
    else:
        feedback_log.append("FAIL: Testing requirement missing (Agent likely accepted the deletion).")

    # (g) "reviewed annually" PRESENT, "semi-annually" ABSENT (13 pts)
    # (The revision changed to semi-annually, so rejection means keeping 'annually')
    if "reviewed annually" in content.lower() and "semi-annually" not in content.lower():
        score += 13
        feedback_log.append("Review frequency change correctly REJECTED (kept annual).")
    else:
        feedback_log.append("FAIL: Review frequency incorrect (Agent likely accepted the change to semi-annual).")

    passed = score >= 60 and revisions_remaining == 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }