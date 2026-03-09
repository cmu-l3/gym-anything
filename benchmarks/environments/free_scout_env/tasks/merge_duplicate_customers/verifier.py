#!/usr/bin/env python3
"""
Verifier for merge_duplicate_customers task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_duplicate_customers(traj, env_info, task_info):
    """
    Verify that two customer profiles were merged correctly.
    
    Criteria:
    1. Target profile (Work ID) MUST exist.
    2. Source profile (Personal ID) MUST NOT exist.
    3. Target profile MUST contain BOTH email addresses.
    4. Global customer count must have decreased by 1.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    feedback_parts = []
    
    # Extract data
    target_exists = result.get('target_profile_exists', False)
    source_exists = result.get('source_profile_exists', True)
    source_email_merged = result.get('expected_source_email_merged', False)
    target_email_present = result.get('expected_target_email_present', False)
    count_reduced = result.get('customer_count_reduced', False)
    count_diff = result.get('count_diff', 0)
    updated_during_task = result.get('target_updated_during_task', False)
    target_emails_raw = result.get('target_associated_emails', '')

    # Criterion 1: Target profile (survivor) must exist (20 pts)
    if target_exists:
        score += 20
        feedback_parts.append("Target profile (Work) preserved")
    else:
        feedback_parts.append("Target profile missing (maybe merged wrong way?)")

    # Criterion 2: Source profile must be gone (20 pts)
    if not source_exists:
        score += 20
        feedback_parts.append("Source profile (Personal) removed/merged")
    else:
        feedback_parts.append("Source profile still exists as separate entity")

    # Criterion 3: Emails Consolidated (30 pts)
    # The surviving profile must have the work email AND the personal email
    if target_exists and source_email_merged and target_email_present:
        score += 30
        feedback_parts.append("Both emails present on target profile")
    elif target_exists and source_email_merged:
        score += 15
        feedback_parts.append("Source email moved, but target email missing (?)")
    elif target_exists and target_email_present:
        feedback_parts.append("Target email present, but source email NOT merged")
    else:
        feedback_parts.append("Email consolidation failed")

    # Criterion 4: Customer Count Check (20 pts)
    # Should decrease by exactly 1
    if count_reduced and count_diff == 1:
        score += 20
        feedback_parts.append("Total customer count decreased by 1")
    elif count_diff > 1:
        score += 10
        feedback_parts.append(f"Customer count decreased by {count_diff} (expected 1)")
    else:
        feedback_parts.append("Customer count did not decrease")

    # Criterion 5: Activity Check (10 pts)
    if updated_during_task:
        score += 10
        feedback_parts.append("Target record modified during task")
    else:
        feedback_parts.append("No modification timestamp on target record")

    # Pass logic: Must have consolidated emails into the correct target
    passed = score >= 70 and target_exists and not source_exists and source_email_merged

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "emails_on_profile": target_emails_raw.replace('\n', ', ')
        }
    }