#!/usr/bin/env python3
"""Verifier for add_customer_alt_email task."""

import json
import tempfile
import os

def verify_add_customer_alt_email(traj, env_info, task_info):
    """
    Verify that the agent added a secondary email to the correct customer profile.
    
    Criteria:
    1. Customer 'Dr. Julian Blackwood' must exist (sanity check).
    2. The new email 'j.blackwood@nexus-corp.com' must be associated with this customer.
    3. The original email 'julian.b@university.local' must STILL be associated (not deleted/replaced).
    4. The total number of emails for this customer should be at least 2.
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_new_email = metadata.get('new_email', 'j.blackwood@nexus-corp.com')
    expected_orig_email = metadata.get('original_email', 'julian.b@university.local')

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
    
    # Check 1: Customer Found (Required for any points)
    if not result.get('customer_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target customer 'Dr. Julian Blackwood' not found in database."
        }
    
    feedback_parts.append("Customer profile found")
    
    # Check 2: New Email Added (40 points)
    has_new = result.get('has_new_email', False)
    if has_new:
        score += 40
        feedback_parts.append(f"New email '{expected_new_email}' successfully added")
    else:
        feedback_parts.append(f"New email '{expected_new_email}' NOT found")

    # Check 3: Original Email Preserved (30 points)
    has_orig = result.get('has_original_email', False)
    if has_orig:
        score += 30
        feedback_parts.append("Original email preserved")
    else:
        feedback_parts.append("Original email was removed/replaced (FAIL)")

    # Check 4: Multiple Emails Exist (30 points)
    # This distinguishes "Adding" from "Replacing" effectively
    email_count = result.get('email_count', 0)
    if email_count >= 2:
        score += 30
        feedback_parts.append(f"Customer has {email_count} emails (Correctly added secondary)")
    else:
        feedback_parts.append(f"Customer only has {email_count} email(s)")

    # Pass logic: Must have added the new one AND kept the old one
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }