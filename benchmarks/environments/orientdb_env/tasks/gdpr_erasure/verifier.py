#!/usr/bin/env python3
"""
Verifier for GDPR Erasure task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gdpr_erasure(traj, env_info, task_info):
    """
    Verifies the GDPR erasure task based on database state and audit file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    old_email_count = result.get("old_email_count", -1)
    initial_stay_count = result.get("initial_stay_count", 0)
    new_profile = result.get("new_profile", {})
    audit = result.get("audit_file", {})

    # Criterion 1: Old Email Removed (15 pts)
    if old_email_count == 0:
        score += 15
        feedback.append("Old email address successfully removed.")
    else:
        feedback.append(f"Old email still exists (Count: {old_email_count}).")

    # Criterion 2: New Profile Exists (15 pts)
    if new_profile.get("found"):
        score += 15
        feedback.append("Anonymized profile found with new email.")
        
        # Criterion 3: PII Anonymized (20 pts)
        pii_score = 0
        if new_profile.get("name") == "Erased": pii_score += 5
        if new_profile.get("surname") == "User": pii_score += 5
        # Gender/Birthday/Nationality should be None or empty
        if not new_profile.get("gender"): pii_score += 3.3
        if not new_profile.get("birthday"): pii_score += 3.3
        if not new_profile.get("nationality"): pii_score += 3.4
        
        score += round(pii_score)
        if pii_score >= 19:
            feedback.append("PII fields correctly anonymized.")
        else:
            feedback.append("Some PII fields were not correctly anonymized.")

        # Criterion 4: Friends Removed (20 pts)
        friend_count = new_profile.get("friend_count", -1)
        if friend_count == 0:
            score += 20
            feedback.append("Social connections (HasFriend) successfully pruned.")
        else:
            feedback.append(f"Social connections still exist (Count: {friend_count}).")

        # Criterion 5: Stays Preserved (20 pts)
        stay_count = new_profile.get("stay_count", -1)
        if stay_count > 0 and stay_count >= initial_stay_count:
            score += 20
            feedback.append("Transactional history (HasStayed) preserved.")
        else:
            feedback.append(f"Transactional history missing or deleted (Initial: {initial_stay_count}, Final: {stay_count}).")

    else:
        feedback.append("Anonymized profile NOT found (Check email spelling?).")

    # Criterion 6: Audit File (10 pts)
    if audit.get("exists") and audit.get("rid_match"):
        score += 10
        feedback.append("Audit log created with correct RID.")
    elif audit.get("exists"):
        score += 5
        feedback.append("Audit log exists but RID is missing or incorrect.")
    else:
        feedback.append("Audit log file not found.")

    # Pass Threshold
    # Must preserve stays to pass (critical business requirement)
    stays_preserved = (new_profile.get("stay_count", 0) >= initial_stay_count) and (initial_stay_count > 0)
    passed = (score >= 70) and stays_preserved

    if not stays_preserved:
        feedback.append("CRITICAL FAIL: Transactional history was lost.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }