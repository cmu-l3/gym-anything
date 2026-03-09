#!/usr/bin/env python3
"""
Verifier for configure_compliance_bcc task.

Verifies that:
1. The Billing mailbox has the correct Auto-BCC address.
2. The Billing mailbox SMTP settings were preserved (not broken).
3. The Decoy (Support) mailbox was not modified.
4. Changes were made during the task window.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_compliance_bcc(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_bcc = metadata.get('expected_bcc', 'audit-vault@acme-finance.com')
    expected_host = metadata.get('expected_smtp_host', 'mail.acme-finance.com')
    
    # 1. Fetch result file
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

    # 2. Extract Data
    task_start = result.get('task_start_timestamp', 0)
    db_state = result.get('db_state', {})
    
    if not db_state.get('billing_exists'):
        return {"passed": False, "score": 0, "feedback": "Critical: Billing mailbox deleted or not found."}

    score = 0
    feedback_parts = []

    # --- Criterion 1: Check Billing BCC (40 pts) ---
    actual_bcc = db_state.get('billing_bcc')
    if actual_bcc == expected_bcc:
        score += 40
        feedback_parts.append("BCC address set correctly")
    elif actual_bcc:
        score += 10
        feedback_parts.append(f"BCC set but incorrect: '{actual_bcc}'")
    else:
        feedback_parts.append("BCC address not set")

    # --- Criterion 2: Check Modification Timestamp (20 pts) ---
    # We allow a small buffer or check if it's strictly > start
    billing_updated_ts = db_state.get('billing_updated_at_ts', 0)
    if billing_updated_ts > task_start:
        score += 20
        feedback_parts.append("Configuration updated during task")
    else:
        feedback_parts.append("No changes detected (timestamp not updated)")

    # --- Criterion 3: Verify SMTP Integrity (20 pts) ---
    # The agent must not break the existing SMTP connection settings
    actual_host = db_state.get('billing_smtp_host')
    pass_set = db_state.get('billing_smtp_pass_set')
    
    if actual_host == expected_host:
        score += 15
        feedback_parts.append("SMTP Host preserved")
    else:
        feedback_parts.append(f"SMTP Host changed/broken (found: {actual_host})")

    if pass_set:
        score += 5
        feedback_parts.append("SMTP Password preserved")
    else:
        feedback_parts.append("SMTP Password cleared/missing")

    # --- Criterion 4: Verify Decoy Mailbox Untouched (20 pts) ---
    support_bcc = db_state.get('support_bcc')
    support_updated_ts = db_state.get('support_updated_at_ts', 0)
    
    if support_bcc is None and support_updated_ts <= task_start:
        score += 20
        feedback_parts.append("Other mailboxes untouched")
    else:
        feedback_parts.append("Decoy mailbox was modified incorrectly")

    # Final Verification
    passed = score >= 80 and actual_bcc == expected_bcc

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }