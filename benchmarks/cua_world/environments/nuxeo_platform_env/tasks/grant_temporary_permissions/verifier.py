#!/usr/bin/env python3
"""
Verifier for grant_temporary_permissions task.

Criteria:
1. User 'contractor_sam' has an ACE (Access Control Entry) in the workspace.
2. Permission is 'ReadWrite'.
3. The permission has an expiration date ('end' field).
4. The expiration date matches '2026-12-31'.
5. VLM: Verify UI interaction via trajectory.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_grant_temporary_permissions(traj, env_info, task_info):
    """
    Verify that the agent granted temporary ReadWrite permissions to contractor_sam.
    """
    # 1. Setup and retrieve data using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_user = metadata.get('target_user', 'contractor_sam')
    target_perm = metadata.get('target_permission', 'ReadWrite')
    target_date = metadata.get('target_expiration_date', '2026-12-31')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse ACL Data
    workspace_doc = result_data.get('workspace_data', {})
    context_params = workspace_doc.get('contextParameters', {})
    acls = context_params.get('acls', [])
    
    # Locate the 'local' ACL (where user permissions are usually added)
    local_acl = next((acl for acl in acls if acl.get('name') == 'local'), None)
    
    score = 0
    feedback_parts = []
    
    if not local_acl:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No local permissions found on the workspace. Did you save the changes?"
        }

    # 3. Find specific ACE for the user
    # ACE structure: {"username": "contractor_sam", "permission": "ReadWrite", "granted": true, "end": "..."}
    sam_ace = None
    aces = local_acl.get('aces', [])
    
    for ace in aces:
        if ace.get('username') == target_user and ace.get('granted') == True:
            sam_ace = ace
            break
            
    if not sam_ace:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No active permission entry found for user '{target_user}'."
        }
    
    score += 25
    feedback_parts.append(f"User '{target_user}' added to permissions")

    # 4. Verify Permission Level
    actual_perm = sam_ace.get('permission')
    if actual_perm == target_perm:
        score += 25
        feedback_parts.append(f"Correct permission '{target_perm}' set")
    else:
        feedback_parts.append(f"Wrong permission level: '{actual_perm}' (expected '{target_perm}')")

    # 5. Verify Expiration Date
    end_date_str = sam_ace.get('end') # Format likely ISO 8601 e.g., 2026-12-31T00:00:00Z
    
    if not end_date_str:
        feedback_parts.append("Permission is permanent (no expiration date set)")
    else:
        score += 25 # Points for setting ANY expiration
        
        # Check specific date match
        # We check if the target date string exists in the timestamp (ignoring time/timezone nuances for simplicity)
        # or parse it properly.
        try:
            # Simple string check first
            if target_date in end_date_str:
                score += 25
                feedback_parts.append(f"Correct expiration date '{target_date}' set")
            else:
                # If string match fails, try parsing to compare YMD
                # Handle standard ISO formats
                # Example: 2026-12-31T05:00:00.000Z
                date_part = end_date_str.split('T')[0]
                if date_part == target_date:
                    score += 25
                    feedback_parts.append(f"Correct expiration date '{target_date}' set")
                else:
                    feedback_parts.append(f"Expiration date '{date_part}' does not match expected '{target_date}'")
        except Exception:
             feedback_parts.append(f"Could not parse expiration date '{end_date_str}'")

    # 6. Final Score Calculation
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }